"""
Fetch yesterday's departures and arrivals for WSI and SYD and store the raw responses.

Each airport/direction/date is upserted into raw.flight_snapshots (see sql/01_create_raw_tables.sql),
so re-running for the same date replaces the row instead of duplicating it.

Source: AeroDataBox via RapidAPI (FIDS / airport schedule endpoint).

Run:  python ingestion/fetch_flights.py
"""

import os
import sys
import time
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

import psycopg
import requests
from dotenv import load_dotenv
from psycopg.types.json import Jsonb

from db import get_connection

AIRPORTS = ["WSI", "SYD"]       
DIRECTIONS = ["departures", "arrivals"]

SYDNEY_TZ = ZoneInfo("Australia/Sydney")
PROJECT_ROOT = Path(__file__).resolve().parent.parent

# AeroDataBox caps each request at a 12-hour window, so one local day = two calls.
DAY_WINDOWS = [("00:00", "11:59"), ("12:00", "23:59")]

# Map our direction names to the API's query value and response key.
API_DIRECTION = {"departures": "Departure", "arrivals": "Arrival"}

REQUEST_TIMEOUT = 30   # seconds
MAX_RETRIES = 3


def load_config():
    """Read the API key and other settings from environment variables (.env locally, secrets in CI)."""
    load_dotenv(PROJECT_ROOT / ".env")  # no-op in CI where .env doesn't exist

    config = {
        "api_key": os.getenv("FLIGHT_API_KEY"),
        "api_host": os.getenv("FLIGHT_API_HOST"),
    }

    if not config["api_key"]:
        sys.exit("FLIGHT_API_KEY is not set. Copy .env.example to .env and fill it in.")

    if not config["api_host"]:
        sys.exit("FLIGHT_API_HOST is not set. Copy .env.example to .env and fill it in.")

    # RapidAPI's X-RapidAPI-Host header must be the bare hostname (aerodatabox.p.rapidapi.com).

    return config


def get_target_date():
    """Return 'yesterday' in Sydney time, so actual times are already filled in."""
    # ZoneInfo handles AEDT (UTC+11) / AEST (UTC+10) switching for us.
    today_in_sydney = datetime.now(SYDNEY_TZ).date()
    return today_in_sydney - timedelta(days=1)


def _get_with_retries(url, headers, params):
    """GET with retries on rate limits (429), server errors (5xx) and network errors."""
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            response = requests.get(url, headers=headers, params=params, timeout=REQUEST_TIMEOUT)
        except (requests.ConnectionError, requests.Timeout) as exc:
            if attempt == MAX_RETRIES:
                raise
            wait = 2 ** attempt
            print(f"    network error ({exc.__class__.__name__}), retrying in {wait}s...")
            time.sleep(wait)
            continue

        if response.status_code == 429 or response.status_code >= 500:
            if attempt == MAX_RETRIES:
                response.raise_for_status()
            # Respect Retry-After if the API sends it, otherwise back off exponentially.
            wait = int(response.headers.get("Retry-After", 2 ** attempt))
            print(f"    HTTP {response.status_code}, retrying in {wait}s...")
            time.sleep(wait)
            continue

        response.raise_for_status()  # other 4xx (bad key, bad params) -> fail fast
        return response


def fetch_board(airport, direction, flight_date, config):
    """Call the API for one airport + direction + date and return the parsed JSON.

    Makes one call per 12-hour window and merges the flight lists into a single payload.
    """
    url = f"https://{config['api_host']}/flights/airports/iata/{airport}"
    headers = {
        "X-RapidAPI-Key": config["api_key"],
        "X-RapidAPI-Host": config["api_host"],
    }
    params = {
        "direction": API_DIRECTION[direction],
        "withLeg": "true",
        "withCancelled": "true",
        "withCodeshared": "true",   # keep codeshares in raw; dedupe later in dbt
        "withCargo": "false",
        "withPrivate": "false",
    }

    flights = []
    for start, end in DAY_WINDOWS:
        window_url = f"{url}/{flight_date}T{start}/{flight_date}T{end}"
        response = _get_with_retries(window_url, headers, params)

        # 204 No Content = no flights in this window (possible at a new airport overnight).
        if response.status_code == 204 or not response.content:
            continue

        flights.extend(response.json().get(direction, []))

    return {
        "airport": airport,
        "direction": direction,
        "flight_date": flight_date.isoformat(),
        "fetched_at": datetime.now(timezone.utc).isoformat(),
        direction: flights,
    }


UPSERT_SQL = """
    INSERT INTO raw.flight_snapshots
        (airport_iata, direction, flight_date, source, fetched_at, payload, flight_count)
    VALUES
        (%(airport)s, %(direction)s, %(flight_date)s, 'aerodatabox', %(fetched_at)s, %(payload)s, %(flight_count)s)
    ON CONFLICT (airport_iata, direction, flight_date) DO UPDATE SET
        source       = EXCLUDED.source,
        fetched_at   = EXCLUDED.fetched_at,
        payload      = EXCLUDED.payload,
        flight_count = EXCLUDED.flight_count
    RETURNING snapshot_id, (xmax = 0) AS inserted
"""


def save_raw(conn, airport, direction, flight_date, payload):
    """Upsert one snapshot into raw.flight_snapshots and commit it.

    Re-running for the same airport/direction/date overwrites that row (newest fetch wins),
    so the job is idempotent. Returns (snapshot_id, "inserted" | "updated").
    """
    flights = payload[direction]
    with conn.transaction():
        snapshot_id, inserted = conn.execute(
            UPSERT_SQL,
            {
                "airport": airport,
                "direction": direction,
                "flight_date": flight_date,
                "fetched_at": payload["fetched_at"],
                "payload": Jsonb(flights),
                "flight_count": len(flights),
            },
        ).fetchone()
    return snapshot_id, "inserted" if inserted else "updated"


def main():
    config = load_config()

    # Optional override for backfills/testing: python ingestion/fetch_flights.py 2026-11-01
    flight_date = date.fromisoformat(sys.argv[1]) if len(sys.argv) > 1 else get_target_date()
    print(f"Fetching flights for {flight_date} (Sydney local date)")

    summary = []
    failures = 0
    # autocommit=True + conn.transaction() per row: each snapshot commits on its own,
    # so one failed airport doesn't roll back the others.
    with get_connection() as conn:
        conn.autocommit = True
        for airport in AIRPORTS:
            for direction in DIRECTIONS:
                print(f"  {airport} {direction}...")
                try:
                    payload = fetch_board(airport, direction, flight_date, config)
                    snapshot_id, action = save_raw(conn, airport, direction, flight_date, payload)
                except (requests.RequestException, psycopg.Error) as exc:
                    print(f"    FAILED: {exc}")
                    failures += 1
                    summary.append((airport, direction, "FAILED"))
                    continue

                count = len(payload[direction])
                summary.append((airport, direction, count))
                print(f"    {count} flights -> raw.flight_snapshots #{snapshot_id} ({action})")

    print("\nSummary")
    for airport, direction, result in summary:
        print(f"  {airport:<4} {direction:<11} {result}")

    # Non-zero exit makes the GitHub Actions run show as failed.
    if failures:
        sys.exit(1)


if __name__ == "__main__":
    main()
