
{{ config(
    materialized='table',
    table_format='delta',
    incremental_strategy='merge',
    unique_key='id',
    merge_update_conditions='id IS NOT NULL',
    merge_delete_conditions='id IS NULL',
    merge_insert_conditions='id IS NOT NULL'
) }}

with events as (
    select
        subscription_event_id,
        user_id,
        event_type,
        case
            when old_plan_id = 'PLAN_BASIC' then 'PLAN_STD'
            when old_plan_id = 'PLAN_PREMIUM' then 'PLAN_PREM'
            else old_plan_id
        end as old_plan_id,
        case
            when new_plan_id = 'PLAN_BASIC' then 'PLAN_STD'
            when new_plan_id = 'PLAN_PREMIUM' then 'PLAN_PREM'
            else new_plan_id
        end as new_plan_id,
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
)

select
    e.subscription_event_id,
    e.user_id,
    e.event_type,
    e.old_plan_id,
    e.new_plan_id,
    e.old_status,
    e.new_status,
    e.event_ts,
    cast(e.event_ts as date) as event_date,
    coalesce(p.monthly_price, e.price) as price,
    coalesce(p.currency, e.currency) as currency,
    e.offer_code,
    e.ingestion_ts
from events e
left join plan_catalog p
    on e.new_plan_id = p.plan_id
