-- One row per physical aircraft movement on a board (WSI/SYD x arrivals/departures).
-- Drops codeshare listings and collapses duplicate listings in the API payload
-- (same flight at two ordinals).
--
-- Why codeshares are dropped rather than matched to their operator:
--   IsCodeshared elements are sparse stubs: ~93% have no callSign and no aircraft
--   reg, ~66% have no other-airport IATA code (name only). They can't be keyed
--   reliably. Only ~25 of ~7.3k codeshare rows have no operator row at the same
--   board + direction + scheduled time, so the operator rows already cover
--   (almost) every physical flight.
--
-- Physical flight key (validated in sql/02_exploration.sql, 3b-3f):
--   board_airport_iata, direction, other_airport_iata, board_scheduled_at, flight_identity
--   * other_airport + scheduled time alone is too coarse: JQ 501 and VA 800 both
--     leave SYD for MEL at 06:00.
--   * flight_identity = call_sign, else aircraft_reg, else flight_number, so rows
--     missing both don't all collapse into one NULL group (a surviving duplicate
--     is safer than a deleted flight).
--
-- Survivor per group: IsOperator > Unknown, then the latest load, then the first
-- listing. Duplicate listings were checked to be identical.

with flights as (

    select * from {{ ref('stg_flights') }}
    -- keeps IsOperator, Unknown and NULL status
    where codeshare_status is distinct from 'IsCodeshared'

),

keyed as (

    select
        *,
        coalesce(call_sign, aircraft_reg, flight_number)            as flight_identity
    from flights

),

with_key as (

    select
        *,
        -- Timestamp rendered in UTC explicitly: casting timestamptz to text uses
        -- the session TimeZone, which would make the hash differ between clients.
        md5(concat_ws('|',
            board_airport_iata,
            direction,
            other_airport_iata,
            to_char(board_scheduled_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS'),
            flight_identity
        ))                                                          as flight_key
    from keyed

),

ranked as (

    select
        *,
        row_number() over (
            partition by flight_key
            order by
                case codeshare_status
                    when 'IsOperator' then 1
                    when 'Unknown'    then 2
                    else 3
                end,
                fetched_at desc,
                flight_ordinal
        )                                                           as row_rank
    from with_key

)

select
    -- keys
    r.flight_key,
    r.flight_identity,

    -- snapshot lineage (of the surviving row)
    r.snapshot_id,
    r.flight_ordinal,
    r.board_airport_iata,
    r.direction,
    r.flight_date,
    r.fetched_at,

    -- flight
    r.flight_number,
    r.call_sign,
    r.status,
    r.codeshare_status,
    r.is_cargo,

    -- airline (operator)
    r.airline_name,
    r.airline_iata,
    r.airline_icao,

    -- aircraft
    r.aircraft_reg,
    r.aircraft_mode_s,
    r.aircraft_model,

    -- route
    r.origin_iata,
    r.destination_iata,
    r.other_airport_iata,
    r.other_airport_icao,
    r.other_airport_name,
    r.other_airport_country,
    r.other_airport_timezone,
    r.other_airport_lat,
    r.other_airport_lon,

    -- departure movement (UTC)
    r.dep_scheduled_at,
    r.dep_revised_at,
    r.dep_runway_at,
    r.dep_terminal,
    r.dep_gate,
    r.dep_check_in_desk,
    r.dep_runway,

    -- arrival movement (UTC)
    r.arr_scheduled_at,
    r.arr_revised_at,
    r.arr_runway_at,
    r.arr_terminal,
    r.arr_gate,
    r.arr_baggage_belt,
    r.arr_runway,

    -- board time
    r.board_scheduled_at,
    r.board_scheduled_local,

    r.flight_json

from ranked as r
where r.row_rank = 1
