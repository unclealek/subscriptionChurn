
{{ config(
    materialized='table',
    table_format='delta',
    incremental_strategy='merge',
    unique_key='id'
) }}

with source_data as (
    select
        genre_id,
        -- Standardize genre names to title case.
        initcap(lower(genre_name)) as genre_name,
        -- Standardize genre groups to title case.
        initcap(lower(genre_group)) as genre_group,
        parent_genre_id,
        -- Convert active flags into booleans.
        cast(is_active as boolean) as is_active,
        -- Keep only one row per genre ID in the final silver model.
        row_number() over (partition by genre_id order by genre_id) as rn
    from {{ source('movie_raw', 'genres') }}

)

select
    genre_id,
    genre_name,
    genre_group,
    parent_genre_id,
    is_active,
    -- Flag root genres that do not roll up to a parent genre.
    case
        when parent_genre_id is null then true
        else false
    end as is_top_level_genre
from source_data
where genre_id is not null
    and rn = 1
