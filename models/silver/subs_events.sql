
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
    subscription_event_id,
    user_id,
    event_type,
    old_plan_id,
    new_plan_id,
    old_status,
    new_status,
    event_ts,
    CAST(event_ts AS DATE) AS event_date,
    price,
    currency,
    offer_code,
    ingestion_ts
FROM {{ source('movie_raw', 'bronze_subscription_events') }}
WHERE event_ts IS NOT NULL
    AND user_id IS NOT NULL
