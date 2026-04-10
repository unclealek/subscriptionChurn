
{{ config(
    materialized='table',
    table_format='delta',
    incremental_strategy='merge',
    unique_key='id'
) }}

with events as (
    select
        subscription_event_id,
        user_id,
        event_type,
        -- Keep old plan IDs aligned to the seed contract.
        old_plan_id,
        -- Keep new plan IDs aligned to the seed contract.
        new_plan_id,
        old_status,
        new_status,
        event_ts,
        price,
        currency,
        offer_code,
        ingestion_ts
    from {{ source('movie_raw', 'bronze_subscription_events') }}
    where event_ts is not null
        and user_id is not null
),

plan_catalog as (
    select
        plan_id,
        monthly_price,
        currency
    from {{ source('movie_raw', 'subscription_plans') }}
),

enriched as (
    select
        e.subscription_event_id,
        e.user_id,
        e.event_type,
        e.old_plan_id,
        e.new_plan_id,
        -- Canonicalize the prior subscription status from the normalized old plan.
        case
            when e.old_plan_id = 'PLAN_FREE' then 'free'
            when e.old_plan_id = 'PLAN_TRIAL' then 'trial'
            when e.old_plan_id = 'PLAN_STD' then 'standard'
            when e.old_plan_id = 'PLAN_PREM' then 'premium'
            when e.old_plan_id = 'PLAN_CANCELLED' then 'cancelled'
            else lower(e.old_status)
        end as old_status,
        -- Canonicalize the next subscription status from the normalized new plan.
        case
            when e.new_plan_id = 'PLAN_FREE' then 'free'
            when e.new_plan_id = 'PLAN_TRIAL' then 'trial'
            when e.new_plan_id = 'PLAN_STD' then 'standard'
            when e.new_plan_id = 'PLAN_PREM' then 'premium'
            when e.new_plan_id = 'PLAN_CANCELLED' then 'cancelled'
            else lower(e.new_status)
        end as new_status,
        -- Classify the plan movement so churn and conversion logic can reuse one field.
        case
            when e.new_plan_id = e.old_plan_id then 'no_change'
            when e.new_plan_id = 'PLAN_CANCELLED' then 'cancel'
            when e.old_plan_id = 'PLAN_CANCELLED' and e.new_plan_id <> 'PLAN_CANCELLED' then 'reactivate'
            when e.old_plan_id is null and e.new_plan_id is not null then 'new_subscription'
            when e.old_plan_id = 'PLAN_FREE' and e.new_plan_id = 'PLAN_TRIAL' then 'trial_start'
            when e.old_plan_id = 'PLAN_TRIAL' and e.new_plan_id in ('PLAN_STD', 'PLAN_PREM') then 'trial_convert'
            when e.old_plan_id in ('PLAN_FREE', 'PLAN_TRIAL', 'PLAN_STD') and e.new_plan_id = 'PLAN_PREM' then 'upgrade'
            when e.old_plan_id in ('PLAN_PREM', 'PLAN_STD', 'PLAN_TRIAL') and e.new_plan_id in ('PLAN_STD', 'PLAN_FREE') then 'downgrade'
            else 'plan_change'
        end as plan_change_type,
        e.event_ts,
        p.monthly_price,
        p.currency as plan_currency,
        e.price,
        e.currency,
        e.offer_code,
        e.ingestion_ts
    from events e
    left join plan_catalog p
        on e.new_plan_id = p.plan_id
)

select
    subscription_event_id,
    user_id,
    event_type,
    old_plan_id,
    new_plan_id,
    old_status,
    new_status,
    plan_change_type,
    event_ts,
    -- Materialize a date grain for partitioning and trend analysis.
    cast(event_ts as date) as event_date,
    -- Prefer the canonical plan price keyed by new_plan_id and fall back to bronze only if unmatched.
    coalesce(monthly_price, price) as price,
    -- Prefer the canonical plan currency keyed by new_plan_id and fall back to bronze only if unmatched.
    coalesce(plan_currency, currency) as currency,
    offer_code,
    ingestion_ts
from enriched
