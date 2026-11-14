"""
Fetch yesterday's departures and arrivals for WSI and SYD and store the raw responses.

Phase 1: save raw JSON to local files.
Phase 2: write to the raw.flight_snapshots table in Postgres instead.

Run:  python ingestion/fetch_flights.py
"""

# TODO: imports you'll likely need: os, json, datetime, requests, dotenv (later: psycopg or sqlalchemy)
import os
import json
from datetime import datetime
from zoneinfo import ZoneInfo
import requests

from dotenv import load_dotenv

AIRPORTS = ["WSI", "SYD"]          # TODO: check whether your API wants IATA or ICAO codes
DIRECTIONS = ["departures", "arrivals"]


def load_config():
    """Read the API key and other settings from environment variables (.env locally, secrets in CI)."""
    # TODO
    pass


def get_target_date():
    """Return 'yesterday' in Sydney time, so actual times are already filled in."""
    # TODO: think about time zones — Sydney is UTC+11 in summer, UTC+10 in winter
    current_time = datetime.now(ZoneInfo("Australia/Sydney"))
    return current_time.date() - datetime.timedelta(days=1)


def fetch_board(airport, direction, flight_date, config):
    """Call the API for one airport + direction + date and return the parsed JSON."""
    # TODO: check whether one call covers a full day or only a time window (you may need 2 calls)
    # TODO: handle errors — bad status codes, timeouts, rate limits
    pass


def save_raw(airport, direction, flight_date, payload):
    """Phase 1: write payload to data/raw/. Phase 2: insert into Postgres."""
    # TODO: re-running for the same date must not create duplicates
    pass


def main():
    # TODO: load config, work out the date, loop over airports x directions, fetch + save, print a summary
    pass


if __name__ == "__main__":
    main()
