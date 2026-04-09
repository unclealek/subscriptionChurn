
{{ config(
    materialized='table',
    table_format='delta',
    incremental_strategy='merge',
    unique_key='id'
) }}

with source_data as (
    select
        device_id,
        -- Standardize device types to lowercase categories.
        lower(device_type) as device_type,
        -- Standardize manufacturer casing for grouping.
        initcap(lower(manufacturer)) as manufacturer,
        -- Normalize OS names while preserving branded capitalization where it matters.
        case
            when lower(os_name) = 'ios' then 'iOS'
            when lower(os_name) = 'macos' then 'macOS'
            when lower(os_name) = 'webos' then 'webOS'
            when lower(os_name) = 'googletv' then 'GoogleTV'
            when lower(os_name) = 'androidtv' then 'AndroidTV'
            when lower(os_name) = 'firefoxos' then 'FirefoxOS'
            when lower(os_name) = 'rokutv' then 'RokuTV'
            else os_name
        end as os_name,
        -- Standardize platform names for filtering.
        lower(app_platform) as app_platform,
        app_version,
        -- Convert active flags into booleans.
        cast(is_active as boolean) as is_active,
        -- Keep only one row per device ID in the final silver model.
        row_number() over (partition by device_id order by device_id) as rn
    from {{ source('movie_raw', 'devices') }}

)

select
    device_id,
    device_type,
    manufacturer,
    os_name,
    app_platform,
    app_version,
    is_active,
    -- Group concrete device types into broader device families.
    case
        when device_type in ('mobile', 'tablet') then 'portable'
        when device_type = 'smart_tv' then 'tv'
        when device_type = 'desktop' then 'computer'
        else 'other'
    end as device_family,
    -- Extract the major app version for coarse release tracking.
    split_part(app_version, '.', 1) as app_major_version
from source_data
where device_id is not null
    and rn = 1
