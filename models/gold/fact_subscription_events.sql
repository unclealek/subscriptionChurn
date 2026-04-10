{{ config(
    materialized='table',
    table_format='delta'
) }}

with subscription_events as (
    select * from {{ ref('subs_events') }}
),

users as (
    select * from {{ ref('users') }}
),

plans as (
    select * from {{ ref('subs_plan') }}
)

select
    se.subscription_event_id,
    se.user_id,
    -- Bring user attributes onto the event fact for segmentation.
    u.country_code as user_country_code,
    u.market as user_market,
    u.acquisition_channel,
    u.age_band,
    u.preferred_device_family,
    se.event_type,
    se.old_plan_id,
    se.new_plan_id,
    -- Join the canonical destination plan attributes used by the event.
    p.plan_name as new_plan_name,
    p.plan_tier as new_plan_tier,
    p.plan_rank as new_plan_rank,
    p.is_paid_plan as new_plan_is_paid,
    se.old_status,
    se.new_status,
    se.plan_change_type,
    se.event_ts,
    se.event_date,
    se.price,
    se.currency,
    se.offer_code,
    se.ingestion_ts
from subscription_events se
left join users u
    on se.user_id = u.user_id
left join plans p
    on se.new_plan_id = p.plan_id
