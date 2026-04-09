
{{ config(
    materialized='table',
    table_format='delta',
    incremental_strategy='merge',
    unique_key='id',
    merge_update_conditions='id IS NOT NULL',
    merge_delete_conditions='id IS NULL',
    merge_insert_conditions='id IS NOT NULL'
) }}

with source_data as (
    select * from {{ source('movie_raw', 'users_seed') }}

)

select
    user_id,
    signup_date,
    country_code,
    market,
    acquisition_channel,
    case
        when initial_plan_id = 'PLAN_BASIC' then 'PLAN_STD'
        when initial_plan_id = 'PLAN_PREMIUM' then 'PLAN_PREM'
        else initial_plan_id
    end as initial_plan_id,
    case
        when initial_plan_id = 'PLAN_FREE' then 'free'
        when initial_plan_id = 'PLAN_TRIAL' then 'trial'
        when initial_plan_id in ('PLAN_STD', 'PLAN_BASIC') then 'standard'
        when initial_plan_id in ('PLAN_PREM', 'PLAN_PREMIUM') then 'premium'
        when initial_plan_id = 'PLAN_CANCELLED' then 'cancelled'
        else lower(initial_subscription_status)
    end as initial_subscription_status,
    age_band,
    preferred_device_type,
    created_at
from source_data
