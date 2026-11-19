-- Phase 3 scratchpad: explore and flatten the raw JSON before moving it into dbt.

-- TODO 1: how many snapshots per airport per day? (sanity check that the job ran)
select
    airport_iata,
    flight_date,
    count(*)         as snapshot_count,   -- rows = snapshots
    sum(flight_count) as flight_count     -- flights inside those snapshots
from raw.flight_snapshots
group by airport_iata, flight_date
order by flight_date desc, airport_iata;

-- TODO 2: unnest the flights array into one row per flight (look up jsonb_array_elements)
select
    s.snapshot_id,
    s.airport_iata,
    s.direction,
    s.flight_date,
    f.flight ->> 'number'         as flight_number,
    f.flight #>> '{aircraft,reg}' as aircraft_reg
from raw.flight_snapshots as s
cross join lateral jsonb_array_elements(s.payload) as f(flight)
limit 50;

-- TODO 3: find codeshares: the same aircraft + scheduled time under several flight numbers
-- Candidate physical-flight key: board_airport_iata, direction, board_scheduled_at, other_airport_iata

-- 3a. Codeshare status distribution
select
    codeshare_status,
    count(*) as row_count
from analytics.stg_flights
group by codeshare_status
order by row_count desc;

-- 3b. Groups with no operator row (would vanish under `where codeshare_status = 'IsOperator'`)
select
    board_airport_iata,
    direction,
    other_airport_iata,
    board_scheduled_at,
    count(*)                                   as row_count,
    array_agg(flight_number || ' (' || coalesce(codeshare_status, 'null') || ')'
              order by flight_number)          as flight_numbers
from analytics.stg_flights
group by board_airport_iata, direction, other_airport_iata, board_scheduled_at
having count(*) filter (where codeshare_status = 'IsOperator') = 0
order by board_scheduled_at;

-- 3c. Groups with MORE than one operator row.
-- Key v2: base key + flight_identity (codeshares share the operator's call_sign / reg;
-- flight_number is the last resort so rows with neither don't collapse into one NULL group).
-- Expect 0 rows, or only window-overlap dupes (same flight_number, same snapshot, different #ordinal).
with keyed as (
    select
        *,
        coalesce(call_sign, aircraft_reg, flight_number) as flight_identity
    from analytics.stg_flights
)
select
    board_airport_iata,
    direction,
    other_airport_iata,
    board_scheduled_at,
    flight_identity,
    count(*)                                   as row_count,
    array_agg(flight_number || ' ' || coalesce(codeshare_status, 'null') || '@' || snapshot_id || '#' || flight_ordinal
              order by snapshot_id, flight_ordinal)          as rows_detail
from keyed
group by board_airport_iata, direction, other_airport_iata, board_scheduled_at, flight_identity
having count(*) filter (where codeshare_status = 'IsOperator') > 1
order by board_scheduled_at;

-- 3d. How many physical flights?
select 
    (select count(*) from analytics.stg_flights) as stg_flight_count,
    count(*) as physical_flight_count
from (
    select distinct
        board_airport_iata,
        direction,
        other_airport_iata,
        board_scheduled_at
    from analytics.stg_flights
) as distinct_flights; 

-- 3e. How many rows have null scheduled time or null other airport?
select 
    count(*) filter (where board_scheduled_at is null) as null_sched,
    count(*) filter (where other_airport_iata is null) as null_other_airport
from analytics.stg_flights;

-- 3f. Do codeshare rows share the operator's call_sign / reg / gate?
select
    board_airport_iata, direction, other_airport_iata, board_scheduled_at,
    flight_number, codeshare_status, airline_iata,
    call_sign, aircraft_reg, dep_terminal, dep_gate, arr_terminal
from analytics.stg_flights
where (board_airport_iata, direction, other_airport_iata, board_scheduled_at) in (
    select board_airport_iata, direction, other_airport_iata, board_scheduled_at
    from analytics.stg_flights
    group by 1, 2, 3, 4
    having count(*) filter (where codeshare_status = 'IsCodeshared') > 0
)
order by board_scheduled_at, board_airport_iata, call_sign, codeshare_status
limit 100;

-- TODO 4: compute delay in minutes (actual - scheduled), converting times to Australia/Sydney
