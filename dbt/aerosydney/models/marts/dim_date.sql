-- One row per Sydney-local calendar day, from WSI's opening (or the first
-- flight, if earlier) to the later of today and the last flight.
-- Mark as the date table in Power BI (date_key).

{% set wsi_opening_date = '2026-10-25' %}

with bounds as (

    select
        least(date '{{ wsi_opening_date }}', min(board_scheduled_local::date))       as start_date,
        greatest((now() at time zone 'Australia/Sydney')::date,
                 max(board_scheduled_local::date))                                   as end_date
    from {{ ref('int_flights_deduped') }}

),

spine as (

    select generate_series(start_date, end_date, interval '1 day')::date as date_key
    from bounds

)

select
    date_key,
    extract(year from date_key)::int                                as year,
    extract(month from date_key)::int                               as month,
    to_char(date_key, 'Mon')                                        as month_name,
    to_char(date_key, 'YYYY-MM')                                    as year_month,
    date_trunc('week', date_key)::date                              as week_start,   -- Monday
    extract(isodow from date_key)::int                              as day_of_week,  -- 1 = Mon
    to_char(date_key, 'Dy')                                         as day_name,
    extract(isodow from date_key) in (6, 7)                         as is_weekend,
    date_key - date '{{ wsi_opening_date }}'                        as days_since_wsi_opening,
    floor((date_key - date '{{ wsi_opening_date }}') / 7.0)::int + 1 as wsi_week_number, -- week 1 = opening week
    date_key >= date '{{ wsi_opening_date }}'                       as is_wsi_open
from spine
