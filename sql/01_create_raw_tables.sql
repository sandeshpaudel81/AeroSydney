-- Phase 2: landing table for raw API responses.
-- Run once in your Neon/Supabase SQL editor.

CREATE SCHEMA IF NOT EXISTS raw;

-- TODO: design raw.flight_snapshots. Think about:
--   * which columns identify one API response (airport, direction, flight date)?
--   * when it was fetched (timestamptz)
--   * the full response body (JSONB)
--   * a unique constraint so re-running the job for the same day can't duplicate data

-- CREATE TABLE raw.flight_snapshots (
--     ...
-- );
