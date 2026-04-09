
{{ config(
    materialized='table',
    table_format='delta',
    incremental_strategy='merge',
    unique_key='id'
) }}

with source_data as (
    select * from {{ source('movie_raw', 'subscription_plans') }}

)

select
    -- Map legacy plan identifiers into the canonical silver plan IDs.
    case
        when plan_id = 'PLAN_BASIC' then 'PLAN_STD'
        when plan_id = 'PLAN_PREMIUM' then 'PLAN_PREM'
        else plan_id
    end as plan_id,
    -- Standardize display casing for downstream reporting.
    initcap(lower(plan_name)) as plan_name,
    -- Keep plan tiers in lowercase for consistent testing and joins.
    lower(plan_tier) as plan_tier,
    -- Normalize billing cycle values to a single casing convention.
    lower(billing_cycle) as billing_cycle,
    -- Cast price to a fixed decimal type before it is reused in facts.
    cast(monthly_price as decimal(10,2)) as monthly_price,
    -- Store currencies in ISO-style uppercase form.
    upper(currency) as currency,
    -- Convert string seed values into booleans.
    cast(ad_supported_flag as boolean) as ad_supported_flag,
    -- Convert stream limits into integers for comparisons.
    cast(concurrent_stream_limit as int) as concurrent_stream_limit,
    -- Convert availability flags into booleans.
    cast(is_active as boolean) as is_active,
    -- Flag plans that generate recurring paid revenue.
    case
        when lower(plan_tier) in ('standard', 'premium') then true
        else false
    end as is_paid_plan,
    -- Flag trial plans explicitly for conversion analysis.
    case
        when lower(plan_tier) = 'trial' then true
        else false
    end as is_trial_plan,
    -- Flag the synthetic cancelled plan state.
    case
        when lower(plan_tier) = 'cancelled' then true
        else false
    end as is_cancelled_plan,
    -- Rank plans so upgrades and downgrades can be derived numerically.
    case
        when lower(plan_tier) in ('free', 'cancelled') then 0
        when lower(plan_tier) = 'trial' then 1
        when lower(plan_tier) = 'standard' then 2
        when lower(plan_tier) = 'premium' then 3
        else null
    end as plan_rank
from source_data
