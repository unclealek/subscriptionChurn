
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
    select
        device_id,
        device_type,
        manufacturer,
        os_name,
        app_platform,
        app_version,
        is_active,
        row_number() over (partition by device_id order by device_id) as rn
    from {{ source('movie_raw', 'devices') }}

)

select *
from source_data
where device_id is not null
