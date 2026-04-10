
{{ config(
    materialized='table',
    table_format='delta',
    incremental_strategy='merge',
    unique_key='id'
) }}

with source_data as (
    select * from {{ source('movie_raw', 'users_seed') }}

),

normalized as (
    select
        user_id,
        -- Parse signup dates into a real date type.
        cast(signup_date as date) as signup_date,
        -- Normalize country codes to uppercase ISO form.
        upper(country_code) as country_code,
        -- Standardize market names for grouping.
        initcap(lower(market)) as market,
        -- Keep channel values lowercase for stable categorization.
        lower(acquisition_channel) as acquisition_channel,
        -- Keep initial plan IDs aligned to the seed contract.
        initial_plan_id,
        -- Derive a canonical status from the seed-backed plan ID and fall back to the raw status only if needed.
        case
            when initial_plan_id = 'PLAN_FREE' then 'free'
            when initial_plan_id = 'PLAN_TRIAL' then 'trial'
            when initial_plan_id = 'PLAN_STD' then 'standard'
            when initial_plan_id = 'PLAN_PREM' then 'premium'
            when initial_plan_id = 'PLAN_CANCELLED' then 'cancelled'
            else lower(initial_subscription_status)
        end as initial_subscription_status,
        age_band,
        -- Normalize device preferences for family-level grouping later.
        lower(preferred_device_type) as preferred_device_type,
        -- Parse creation timestamps into a timestamp type.
        cast(created_at as timestamp) as created_at
    from source_data
),

plan_catalog as (
    select
        -- Keep plan IDs aligned to the seed contract before joining into users.
        plan_id,
        -- Standardize display casing before joining into the user dimension.
        initcap(lower(plan_name)) as plan_name,
        -- Keep tiers lowercase for downstream filters.
        lower(plan_tier) as plan_tier,
        -- Cast monthly prices to a fixed decimal type.
        cast(monthly_price as decimal(10,2)) as monthly_price,
        -- Store currencies in uppercase form.
        upper(currency) as currency
    from {{ source('movie_raw', 'subscription_plans') }}
)

select
    n.user_id,
    n.signup_date,
    -- Derive a month grain for cohort analysis.
    date_trunc('month', n.signup_date) as signup_month,
    n.country_code,
    n.market,
    n.acquisition_channel,
    n.initial_plan_id,
    n.initial_subscription_status,
    -- Bring in the canonical plan name from the cleaned plan catalog.
    p.plan_name as initial_plan_name,
    -- Bring in the canonical plan tier from the cleaned plan catalog.
    p.plan_tier as initial_plan_tier,
    -- Expose the standardized starting price for the user.
    p.monthly_price as initial_monthly_price,
    -- Expose the standardized starting currency for the user.
    p.currency as initial_plan_currency,
    -- Flag whether the user's starting plan is paid.
    case
        when p.plan_tier in ('standard', 'premium') then true
        else false
    end as is_paid_subscriber,
    n.age_band,
    n.preferred_device_type,
    -- Collapse device types into broader families for segmentation.
    case
        when n.preferred_device_type in ('mobile', 'tablet') then 'portable'
        when n.preferred_device_type = 'smart_tv' then 'tv'
        when n.preferred_device_type = 'desktop' then 'computer'
        else 'other'
    end as preferred_device_family,
    n.created_at
from normalized n
left join plan_catalog p
    on n.initial_plan_id = p.plan_id
