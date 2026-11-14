-- Phase 2: landing table for raw API responses.
-- Run once (safe to re-run) in the Neon SQL editor, or with the direct (unpooled) connection.

CREATE SCHEMA IF NOT EXISTS raw;

-- One row = one airport + direction + Sydney-local flight date, as fetched from AeroDataBox.
CREATE TABLE IF NOT EXISTS raw.flight_snapshots (
    snapshot_id   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    airport_iata  char(3)     NOT NULL,
    direction     text        NOT NULL CHECK (direction IN ('departures', 'arrivals')),
    flight_date   date        NOT NULL,          -- local date in Australia/Sydney

    source        text        NOT NULL DEFAULT 'aerodatabox',
    fetched_at    timestamptz NOT NULL DEFAULT now(),

    -- The data: JSON array of flight objects, merged from the two 12-hour API windows.
    payload       jsonb       NOT NULL CHECK (jsonb_typeof(payload) = 'array'),
    flight_count  integer     NOT NULL,          

    CONSTRAINT flight_snapshots_natural_key UNIQUE (airport_iata, direction, flight_date)
);

COMMENT ON TABLE raw.flight_snapshots IS
    'Raw AeroDataBox airport board responses, one row per airport/direction/date. Upserted daily.';
