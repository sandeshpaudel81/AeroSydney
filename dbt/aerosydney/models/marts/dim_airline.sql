-- One row per operating airline.
-- Key falls back IATA -> ICAO -> name: business-jet / charter operators often
-- have no IATA code, and a few have only a name (e.g. 'TFX').
-- mode() picks the most common spelling ('Malaysia' vs 'Malaysia Airlines').

with flights as (

    select * from {{ ref('int_flights_deduped') }}

)

select
    coalesce(airline_iata, airline_icao, airline_name)              as airline_key,
    mode() within group (order by airline_iata)                     as airline_iata,
    mode() within group (order by airline_icao)                     as airline_icao,
    mode() within group (order by airline_name)                     as airline_name,
    count(*)                                                        as flights_observed
from flights
group by 1
