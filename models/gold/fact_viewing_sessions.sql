{{ config(
    materialized='table',
    table_format='delta'
) }}

with viewing_sessions as (
    select * from {{ ref('view_sess') }}
),

users as (
    select * from {{ ref('users') }}
),

devices as (
    select * from {{ ref('user_devices') }}
),

content as (
    select * from {{ ref('content') }}
),

subscription_events as (
    select * from {{ ref('subs_events') }}
),

latest_subscription_event as (
    select
        vs.session_id,
        se.subscription_event_id,
        se.new_plan_id,
        se.new_status,
        se.plan_change_type,
        se.event_ts as latest_subscription_event_ts,
        row_number() over (
            partition by vs.session_id
            order by se.event_ts desc, se.subscription_event_id desc
        ) as rn
    from viewing_sessions vs
    left join subscription_events se
        on vs.user_id = se.user_id
        and se.event_ts <= vs.session_start_ts
)

select
    vs.session_id,
    vs.user_id,
    -- Bring user attributes onto the session fact for behavioral analysis.
    u.country_code as user_country_code,
    u.market as user_market,
    u.acquisition_channel,
    u.age_band,
    u.preferred_device_family as user_preferred_device_family,
    vs.device_id,
    -- Bring device attributes onto the session fact.
    d.device_type,
    d.device_family,
    d.manufacturer,
    d.os_name,
    d.app_platform,
    d.app_major_version,
    vs.content_id,
    -- Bring content attributes onto the session fact.
    c.title as content_title,
    c.genre_id,
    c.subgenre,
    c.content_type,
    c.runtime_bucket,
    c.language,
    c.age_rating,
    c.is_kids_content,
    -- Attach the user's latest subscription state at the time of the session.
    lse.subscription_event_id as latest_subscription_event_id,
    lse.new_plan_id as session_plan_id,
    lse.new_status as session_subscription_status,
    lse.plan_change_type as latest_plan_change_type,
    lse.latest_subscription_event_ts,
    vs.session_start_ts,
    vs.session_end_ts,
    vs.watch_minutes,
    vs.session_duration_minutes,
    vs.completion_pct,
    vs.completion_bucket,
    vs.autoplay_flag,
    vs.is_logged_in,
    vs.session_date,
    vs.session_quality_flag,
    vs.ingestion_ts
from viewing_sessions vs
left join users u
    on vs.user_id = u.user_id
left join devices d
    on vs.device_id = d.device_id
left join content c
    on vs.content_id = c.content_id
left join latest_subscription_event lse
    on vs.session_id = lse.session_id
    and lse.rn = 1
