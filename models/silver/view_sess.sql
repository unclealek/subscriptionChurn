
{{ config(
    materialized='table',
    table_format='delta',
    incremental_strategy='merge',
    unique_key='id'
) }}

with source_data as (
    select
        session_id,
        user_id,
        device_id,
        content_id,
        -- Parse session timestamps into typed timestamp fields.
        cast(session_start_ts as timestamp) as session_start_ts,
        cast(session_end_ts as timestamp) as session_end_ts,
        -- Cast watch time into an integer minute value.
        cast(watch_minutes as int) as watch_minutes,
        -- Cast completion percentages to a bounded decimal-friendly type.
        cast(completion_pct as decimal(5,2)) as completion_pct,
        -- Convert raw playback flags into booleans.
        cast(autoplay_flag as boolean) as autoplay_flag,
        cast(is_logged_in as boolean) as is_logged_in,
        -- Normalize country codes for geographic reporting.
        upper(country_code) as country_code,
        -- Materialize the session date as a date type.
        cast(session_date as date) as session_date,
        -- Parse ingestion timestamps into a timestamp type.
        cast(ingestion_ts as timestamp) as ingestion_ts
    from {{ source('movie_raw', 'bronze_viewing_sessions') }}
    where session_start_ts is not null
        and user_id is not null
        and device_id is not null
        and content_id is not null
),

enriched as (
    select
        *,
        -- Derive elapsed session length from start and end timestamps when they are valid.
        case
            when session_end_ts >= session_start_ts
                then round((unix_timestamp(session_end_ts) - unix_timestamp(session_start_ts)) / 60.0, 2)
            else null
        end as session_duration_minutes
    from source_data
)

select
    session_id,
    user_id,
    device_id,
    content_id,
    session_start_ts,
    session_end_ts,
    watch_minutes,
    session_duration_minutes,
    -- Clamp completion percentages into the expected 0-100 range.
    case
        when completion_pct < 0 then cast(0 as decimal(5,2))
        when completion_pct > 100 then cast(100 as decimal(5,2))
        else completion_pct
    end as completion_pct,
    -- Bucket completion to make retention-style analysis easier.
    case
        when completion_pct < 25 then '0_24'
        when completion_pct < 50 then '25_49'
        when completion_pct < 75 then '50_74'
        else '75_100'
    end as completion_bucket,
    autoplay_flag,
    is_logged_in,
    country_code,
    session_date,
    -- Flag rows where watch time and timestamps are not internally consistent.
    case
        when session_duration_minutes is null then 'invalid_timestamps'
        when watch_minutes > session_duration_minutes then 'watch_gt_duration'
        else 'valid'
    end as session_quality_flag,
    ingestion_ts
from enriched
