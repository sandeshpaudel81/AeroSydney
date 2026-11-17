-- One row per flight element in raw.flight_snapshots.payload (codeshares included;
-- deduped in int_flights_deduped). Ported from sql/03_create_flights_view.sql.
--
-- Payload notes (AeroDataBox FIDS, withLeg=true):
--   * Each element has a `departure` and an `arrival` movement.
--   * The movement at the board airport has no `airport` object (it's airport_iata),
--     so origin/destination are derived from `direction`.
--   * Times look like '2026-11-13 19:35Z' and cast straight to timestamptz.
--     Many fields are optional (gate, runwayTime, aircraft.reg...), so expect NULLs.

with snapshots as (

    select * from {{ source('raw', 'flight_snapshots') }}

),

flattened as (

    select
        -- snapshot lineage
        s.snapshot_id,
        f.flight_ordinal,
        s.airport_iata                                              as board_airport_iata,
        s.direction,
        s.flight_date,
        s.fetched_at,

        -- flight
        f.flight ->> 'number'                                       as flight_number,
        f.flight ->> 'callSign'                                     as call_sign,
        f.flight ->> 'status'                                       as status,
        f.flight ->> 'codeshareStatus'                              as codeshare_status,
        (f.flight ->> 'isCargo')::boolean                           as is_cargo,

        -- airline
        f.flight #>> '{airline,name}'                               as airline_name,
        f.flight #>> '{airline,iata}'                               as airline_iata,
        f.flight #>> '{airline,icao}'                               as airline_icao,

        -- aircraft
        f.flight #>> '{aircraft,reg}'                               as aircraft_reg,
        f.flight #>> '{aircraft,modeS}'                             as aircraft_mode_s,
        f.flight #>> '{aircraft,model}'                             as aircraft_model,

        -- route (board airport fills in the side the API leaves out)
        case when s.direction = 'departures' then s.airport_iata
             else f.flight #>> '{departure,airport,iata}' end       as origin_iata,
        case when s.direction = 'arrivals'   then s.airport_iata
             else f.flight #>> '{arrival,airport,iata}'   end       as destination_iata,

        -- the other airport (always present on the non-board side)
        o.airport ->> 'iata'                                        as other_airport_iata,
        o.airport ->> 'icao'                                        as other_airport_icao,
        o.airport ->> 'name'                                        as other_airport_name,
        upper(o.airport ->> 'countryCode')                          as other_airport_country,
        o.airport ->> 'timeZone'                                    as other_airport_timezone,
        (o.airport #>> '{location,lat}')::numeric                   as other_airport_lat,
        (o.airport #>> '{location,lon}')::numeric                   as other_airport_lon,

        -- departure movement (UTC)
        (f.flight #>> '{departure,scheduledTime,utc}')::timestamptz as dep_scheduled_at,
        (f.flight #>> '{departure,revisedTime,utc}')::timestamptz   as dep_revised_at,
        (f.flight #>> '{departure,runwayTime,utc}')::timestamptz    as dep_runway_at,
        f.flight #>> '{departure,terminal}'                         as dep_terminal,
        f.flight #>> '{departure,gate}'                             as dep_gate,
        f.flight #>> '{departure,checkInDesk}'                      as dep_check_in_desk,
        f.flight #>> '{departure,runway}'                           as dep_runway,

        -- arrival movement (UTC)
        (f.flight #>> '{arrival,scheduledTime,utc}')::timestamptz   as arr_scheduled_at,
        (f.flight #>> '{arrival,revisedTime,utc}')::timestamptz     as arr_revised_at,
        (f.flight #>> '{arrival,runwayTime,utc}')::timestamptz      as arr_runway_at,
        f.flight #>> '{arrival,terminal}'                           as arr_terminal,
        f.flight #>> '{arrival,gate}'                               as arr_gate,
        f.flight #>> '{arrival,baggageBelt}'                        as arr_baggage_belt,
        f.flight #>> '{arrival,runway}'                             as arr_runway,

        -- original element, for debugging anything not flattened above
        f.flight                                                    as flight_json

    from snapshots as s
    cross join lateral jsonb_array_elements(s.payload)
        with ordinality as f(flight, flight_ordinal)
    cross join lateral (
        select case when s.direction = 'departures'
                    then f.flight #> '{arrival,airport}'
                    else f.flight #> '{departure,airport}' end as airport
    ) as o

)

select
    *,

    -- The movement at the board airport (WSI/SYD): departure time for departures,
    -- arrival time for arrivals. This is the time the board shows.
    case when direction = 'departures' then dep_scheduled_at
         else arr_scheduled_at end                                  as board_scheduled_at,

    -- Same instant as Sydney wall-clock time (timestamp without tz, DST applied).
    -- Use for local hour / curfew / local day; use the UTC columns for delay maths.
    (case when direction = 'departures' then dep_scheduled_at
          else arr_scheduled_at end) at time zone 'Australia/Sydney' as board_scheduled_local

from flattened
