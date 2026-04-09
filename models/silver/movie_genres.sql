
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
        genre_id,
        genre_name,
        genre_group,
        parent_genre_id,
        is_active,
        row_number() over (partition by genre_id order by genre_id) as rn
    from {{ source('movie_raw', 'genres') }}

)

select *
from source_data
where genre_id is not null
