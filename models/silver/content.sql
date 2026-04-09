
{{ config(
    materialized='table',
    table_format='delta',
    incremental_strategy='merge',
    unique_key='id'
) }}

with source_data as (
    select * from {{ source('movie_raw', 'content_catalog') }}

)

select
    content_id,
    -- Remove leading and trailing whitespace from titles.
    trim(title) as title,
    genre_id,
    -- Standardize subgenre casing for cleaner grouping.
    initcap(trim(subgenre)) as subgenre,
    -- Keep content types lowercase for stable filtering.
    lower(content_type) as content_type,
    -- Cast release years to integers for arithmetic.
    cast(release_year as int) as release_year,
    -- Cast durations to integers for bucketing.
    cast(duration_minutes as int) as duration_minutes,
    -- Standardize language labels to title case.
    initcap(lower(language)) as language,
    -- Cast age ratings to integers for comparisons.
    cast(age_rating as int) as age_rating,
    -- Convert string flags into booleans.
    cast(is_kids_content as boolean) as is_kids_content,
    -- Convert availability flags into booleans.
    cast(is_active as boolean) as is_active,
    -- Derive the current age of the content in years.
    year(current_date()) - cast(release_year as int) as content_age_years,
    -- Bucket content by runtime to simplify catalog analysis.
    case
        when lower(content_type) = 'live' then 'live_event'
        when cast(duration_minutes as int) < 30 then 'short_form'
        when cast(duration_minutes as int) < 90 then 'standard'
        else 'feature_length'
    end as runtime_bucket
from source_data
