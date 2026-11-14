"""
Postgres (Neon) connection helper.

DATABASE_URL is the pooled connection string, the right one for app traffic like the daily job.
DATABASE_URL_UNPOOLED is the direct connection; use it for schema migrations / long sessions.
Locally both come from .env (written by `neon deploy`); in CI add DATABASE_URL as a repo secret.

Check the connection:  python ingestion/db.py
"""

import os
import sys
from pathlib import Path

import psycopg
from dotenv import load_dotenv

PROJECT_ROOT = Path(__file__).resolve().parent.parent


def get_database_url(unpooled=False):
    """Get the Neon connection string from the environment."""
    load_dotenv(PROJECT_ROOT / ".env")
    key = "DATABASE_URL_UNPOOLED" if unpooled else "DATABASE_URL"
    url = os.getenv(key)
    if not url:
        sys.exit(f"{key} is not set. Run `neon env pull` or add it to .env / CI secrets.")
    return url


def get_connection(unpooled=False):
    """Open a psycopg connection. Use as a context manager: `with get_connection() as conn:`

    Neon computes scale to zero, so the first connection after idle can take a few seconds.
    """
    return psycopg.connect(get_database_url(unpooled), connect_timeout=15)


if __name__ == "__main__":
    with get_connection() as conn:
        row = conn.execute(
            "select current_database(), current_user, split_part(version(), ' ', 2)"
        ).fetchone()
    print(f"Connected to database={row[0]} as user={row[1]} (Postgres {row[2]})")
