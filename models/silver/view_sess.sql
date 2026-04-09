
{{ config(
    materialized='table',
    table_format='delta',
    incremental_strategy='merge',
    unique_key='id',
    merge_update_conditions='id IS NOT NULL',
    merge_delete_conditions='id IS NULL',
    merge_insert_conditions='id IS NOT NULL'
) }}

SELECT
    session_id,
    user_id,
    device_id,
    content_id,
    session_start_ts,
    session_end_ts,
    watch_minutes,
    completion_pct,
    autoplay_flag,
    is_logged_in,
    country_code,
    CAST(session_date AS DATE) AS session_date,
    ingestion_ts
FROM {{ source('movie_raw', 'bronze_viewing_sessions') }}
WHERE session_start_ts IS NOT NULL
    AND user_id IS NOT NULL
    AND device_id IS NOT NULL
    AND content_id IS NOT NULL
