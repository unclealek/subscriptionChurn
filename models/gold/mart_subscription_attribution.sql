{{ config(
    materialized='table',
    table_format='delta'
) }}

with subscription_events as (
    select * from {{ ref('fact_subscription_events') }}
),

viewing_sessions as (
    select * from {{ ref('fact_viewing_sessions') }}
),

lookback_sessions as (
    select
        fse.subscription_event_id,
        fse.user_id,
        fse.event_ts,
        fse.event_date,
        fse.new_plan_id,
        fse.new_plan_name,
        fse.new_plan_tier,
        fvs.session_id,
        fvs.content_id,
        fvs.content_title,
        fvs.genre_id,
        fvs.watch_minutes,
        fvs.session_start_ts,
        row_number() over (
            partition by fse.subscription_event_id
            order by fvs.session_start_ts desc, fvs.session_id desc
        ) as recency_rank
    from subscription_events fse
    left join {{ ref('fact_viewing_sessions') }} fvs
        on fse.user_id = fvs.user_id
        and fvs.session_start_ts <= fse.event_ts
        and fvs.session_start_ts > fse.event_ts - interval 24 hours
),

last_watched as (
    select
        subscription_event_id,
        -- Take the most recent title watched in the 24-hour lookback.
        content_title as attributed_last_title
    from lookback_sessions
    where recency_rank = 1
),

title_rollup as (
    select
        subscription_event_id,
        content_title,
        sum(watch_minutes) as title_watch_minutes,
        row_number() over (
            partition by subscription_event_id
            order by sum(watch_minutes) desc, content_title
        ) as rn
    from lookback_sessions
    where content_title is not null
    group by 1, 2
),

top_title as (
    select
        subscription_event_id,
        -- Pick the title with the highest watch time inside the lookback window.
        content_title as attributed_most_watched_title
    from title_rollup
    where rn = 1
),

genre_rollup as (
    select
        subscription_event_id,
        genre_id,
        sum(watch_minutes) as genre_watch_minutes,
        row_number() over (
            partition by subscription_event_id
            order by sum(watch_minutes) desc, genre_id
        ) as rn
    from lookback_sessions
    where genre_id is not null
    group by 1, 2
),

top_genre as (
    select
        subscription_event_id,
        -- Pick the genre with the highest watch time inside the lookback window.
        genre_id as attributed_most_watched_genre
    from genre_rollup
    where rn = 1
),

watch_summary as (
    select
        subscription_event_id,
        -- Sum all minutes watched in the attribution lookback period.
        coalesce(sum(watch_minutes), 0) as total_watch_minutes_before_signup,
        -- Count distinct titles consumed before the subscription event.
        count(distinct content_id) as number_of_titles_watched
    from lookback_sessions
    group by 1
)

select
    fse.subscription_event_id,
    fse.user_id,
    fse.event_ts,
    fse.event_date,
    fse.new_plan_id,
    fse.new_plan_name,
    fse.new_plan_tier,
    lw.attributed_last_title as attributed_title,
    tt.attributed_most_watched_title as most_watched_title,
    tg.attributed_most_watched_genre as attributed_genre,
    ws.total_watch_minutes_before_signup,
    ws.number_of_titles_watched,
    -- Label how attribution was assigned based on the available watch history.
    case
        when ws.total_watch_minutes_before_signup = 0 then 'no_recent_viewing'
        when tt.attributed_most_watched_title is not null then 'most_watched_title_24h'
        when lw.attributed_last_title is not null then 'last_watched_title_24h'
        else 'fallback'
    end as attribution_method
from subscription_events fse
left join last_watched lw
    on fse.subscription_event_id = lw.subscription_event_id
left join top_title tt
    on fse.subscription_event_id = tt.subscription_event_id
left join top_genre tg
    on fse.subscription_event_id = tg.subscription_event_id
left join watch_summary ws
    on fse.subscription_event_id = ws.subscription_event_id
