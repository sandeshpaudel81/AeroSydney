-- Phase 3: flatten raw.flight_snapshots.payload into one row per flight.
-- Safe to re-run. Codeshares are kept (one row per flight number); dedupe them downstream.
--
-- Payload notes (AeroDataBox FIDS, withLeg=true):
--   * Each element has a `departure` and an `arrival` movement.
--   * The movement at the board airport has no `airport` object (it's s.airport_iata),
--     so origin/destination are derived from `direction`.
--   * Times look like '2026-11-13 19:35Z', which casts straight to timestamptz.
--     Many fields are optional (gate, runwayTime, aircraft.reg...), so expect NULLs.

CREATE SCHEMA IF NOT EXISTS staging;

CREATE OR REPLACE VIEW staging.v_flights AS
SELECT
    -- snapshot lineage
    s.snapshot_id,
    f.flight_ordinal,
    s.airport_iata                                       AS board_airport_iata,
    s.direction,
    s.flight_date,
    s.fetched_at,

    -- flight
    f.flight ->> 'number'                                AS flight_number,
    f.flight ->> 'callSign'                              AS call_sign,
    f.flight ->> 'status'                                AS status,
    f.flight ->> 'codeshareStatus'                       AS codeshare_status,
    (f.flight ->> 'isCargo')::boolean                    AS is_cargo,

    -- airline
    f.flight #>> '{airline,name}'                        AS airline_name,
    f.flight #>> '{airline,iata}'                        AS airline_iata,
    f.flight #>> '{airline,icao}'                        AS airline_icao,

    -- aircraft
    f.flight #>> '{aircraft,reg}'                        AS aircraft_reg,
    f.flight #>> '{aircraft,modeS}'                      AS aircraft_mode_s,
    f.flight #>> '{aircraft,model}'                      AS aircraft_model,

    -- route (board airport fills in the side the API leaves out)
    CASE WHEN s.direction = 'departures' THEN s.airport_iata
         ELSE f.flight #>> '{departure,airport,iata}' END AS origin_iata,
    CASE WHEN s.direction = 'arrivals'   THEN s.airport_iata
         ELSE f.flight #>> '{arrival,airport,iata}'   END AS destination_iata,

    -- the other airport (always present on the non-board side)
    o.airport ->> 'iata'                                 AS other_airport_iata,
    o.airport ->> 'icao'                                 AS other_airport_icao,
    o.airport ->> 'name'                                 AS other_airport_name,
    upper(o.airport ->> 'countryCode')                   AS other_airport_country,
    o.airport ->> 'timeZone'                             AS other_airport_timezone,
    (o.airport #>> '{location,lat}')::numeric            AS other_airport_lat,
    (o.airport #>> '{location,lon}')::numeric            AS other_airport_lon,

    -- departure movement
    (f.flight #>> '{departure,scheduledTime,utc}')::timestamptz AS dep_scheduled_at,
    (f.flight #>> '{departure,revisedTime,utc}')::timestamptz   AS dep_revised_at,
    (f.flight #>> '{departure,runwayTime,utc}')::timestamptz    AS dep_runway_at,
    f.flight #>> '{departure,terminal}'                  AS dep_terminal,
    f.flight #>> '{departure,gate}'                      AS dep_gate,
    f.flight #>> '{departure,checkInDesk}'               AS dep_check_in_desk,
    f.flight #>> '{departure,runway}'                    AS dep_runway,

    -- arrival movement
    (f.flight #>> '{arrival,scheduledTime,utc}')::timestamptz   AS arr_scheduled_at,
    (f.flight #>> '{arrival,revisedTime,utc}')::timestamptz     AS arr_revised_at,
    (f.flight #>> '{arrival,runwayTime,utc}')::timestamptz      AS arr_runway_at,
    f.flight #>> '{arrival,terminal}'                    AS arr_terminal,
    f.flight #>> '{arrival,gate}'                        AS arr_gate,
    f.flight #>> '{arrival,baggageBelt}'                 AS arr_baggage_belt,
    f.flight #>> '{arrival,runway}'                      AS arr_runway,

    -- original element, for debugging anything not flattened above
    f.flight                                             AS flight_json
FROM raw.flight_snapshots AS s
CROSS JOIN LATERAL jsonb_array_elements(s.payload) WITH ORDINALITY AS f(flight, flight_ordinal)
CROSS JOIN LATERAL (
    SELECT CASE WHEN s.direction = 'departures'
                THEN f.flight #> '{arrival,airport}'
                ELSE f.flight #> '{departure,airport}' END AS airport
) AS o;

COMMENT ON VIEW staging.v_flights IS
    'One row per flight (codeshares included) flattened from raw.flight_snapshots.payload. Times are UTC timestamptz.';
