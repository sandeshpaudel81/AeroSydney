-- One row per "other" airport (the far end of a WSI/SYD flight).
-- Attributes come from the flight payloads; mode() picks the most common value
-- when the API spells an airport two ways.
-- Flights whose far end has no IATA code (~3%, mostly 'Unknown') share one
-- UNKNOWN row so every fact row still joins.

with flights as (

    select * from {{ ref('int_flights_deduped') }}

),

known as (

    select
        other_airport_iata                                          as airport_key,
        other_airport_iata                                          as airport_iata,
        mode() within group (order by other_airport_icao)           as airport_icao,
        mode() within group (order by other_airport_name)           as airport_name,
        mode() within group (order by other_airport_country)        as country_code,
        mode() within group (order by other_airport_timezone)       as timezone,
        mode() within group (order by other_airport_lat)            as latitude,
        mode() within group (order by other_airport_lon)            as longitude
    from flights
    where other_airport_iata is not null
    group by other_airport_iata

),

unknown as (

    select
        'UNKNOWN'::text                                             as airport_key,
        null::text                                                  as airport_iata,
        null::text                                                  as airport_icao,
        'Unknown / no IATA code'::text                              as airport_name,
        null::text                                                  as country_code,
        null::text                                                  as timezone,
        null::numeric                                               as latitude,
        null::numeric                                               as longitude

)

select
    *,
    case when country_code is null then null
         else country_code = 'AU' end                               as is_domestic
from (
    select * from known
    union all
    select * from unknown
) as airports
