-- Phase 3 scratchpad: explore and flatten the raw JSON before moving it into dbt.

-- TODO 1: how many snapshots per airport per day? (sanity check that the job ran)

-- TODO 2: unnest the flights array into one row per flight (look up jsonb_array_elements)

-- TODO 3: find codeshares: the same aircraft + scheduled time under several flight numbers

-- TODO 4: compute delay in minutes (actual - scheduled), converting times to Australia/Sydney
