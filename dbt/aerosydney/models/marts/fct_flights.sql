-- One row per physical aircraft movement on a board (WSI/SYD x arrivals/departures).
-- Star-schema fact for Power BI: descriptive airport/airline attributes live in
-- dim_airport / dim_airline; join on other_airport_key / airline_key / date_key.
--
-- Delay definitions (minutes, positive = late), measured at the board airport:
--   * delay_minutes:        revised (gate) time - scheduled. Industry on-time
--                           standard (on time = within 15 min of schedule).
--   * runway_delay_minutes: runway (wheels-off / touchdown) time - scheduled.
--                           Includes taxi time (~22 min median at SYD), so it
--                           reads later than delay_minutes.
--   Both only for completed flights (Departed / Arrived).
--   Caveat: the API often leaves departure revisedTime equal to scheduled
--   (~61% of SYD departures, some of which took off 60+ min late), so departure
--   delay_minutes understates delays. Arrival revised times are updated ~92% of
--   the time; prefer arrivals for punctuality comparisons.

with flights as (

    select * from {{ ref('int_flights_deduped') }}

),

movements as (

    select
        *,
        -- the board-airport side of the flight
        case when direction = 'departures' then dep_revised_at else arr_revised_at end as board_revised_at,
        case when direction = 'departures' then dep_runway_at  else arr_runway_at  end as board_runway_at,
        case when direction = 'departures' then dep_terminal   else arr_terminal   end as board_terminal,
        status in ('Departed', 'Arrived')                                             as is_completed
    from flights

),

delays as (

    select
        *,
        case when is_completed then
            round(extract(epoch from (board_revised_at - board_scheduled_at)) / 60)::int
        end                                                         as delay_minutes,
        case when is_completed then
            round(extract(epoch from (board_runway_at - board_scheduled_at)) / 60)::int
        end                                                         as runway_delay_minutes
    from movements

)

select
    -- keys
    flight_key,
    board_scheduled_local::date                                     as date_key,
    -- no IATA code (e.g. 'Unknown' strips, small fields): grouped as UNKNOWN in dim_airport
    coalesce(other_airport_iata, 'UNKNOWN')                         as other_airport_key,
    coalesce(airline_iata, airline_icao, airline_name)              as airline_key,

    -- flight
    board_airport_iata,
    direction,
    flight_number,
    call_sign,
    status,
    aircraft_reg,
    aircraft_model,
    origin_iata,
    destination_iata,
    board_terminal,

    -- times at the board airport (UTC, plus Sydney local for the schedule)
    board_scheduled_at,
    board_scheduled_local,
    extract(hour from board_scheduled_local)::int                   as scheduled_local_hour,
    board_revised_at,
    board_runway_at,

    -- punctuality
    delay_minutes,
    runway_delay_minutes,
    case when delay_minutes is not null then delay_minutes <= 15 end as is_on_time,

    -- flags
    is_completed,
    status = 'Canceled'                                             as is_cancelled,
    -- 23:00-06:00 local: SYD's curfew hours; WSI operates 24/7
    board_scheduled_local::time >= time '23:00'
        or board_scheduled_local::time < time '06:00'               as is_curfew_window,

    -- lineage
    snapshot_id,
    fetched_at

from delays
