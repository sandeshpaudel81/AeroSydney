-- Flags implausible delays (more than 1h early or 24h late): usually a bad
-- timestamp in the API payload rather than a real delay. Warn, don't fail.
{{ config(severity = 'warn') }}

select
    flight_key,
    flight_number,
    board_scheduled_at,
    delay_minutes,
    runway_delay_minutes
from {{ ref('fct_flights') }}
where delay_minutes        not between -60 and 1440
   or runway_delay_minutes not between -60 and 1440
