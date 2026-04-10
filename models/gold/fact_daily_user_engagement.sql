{{ config(
    materialized='table',
    table_format='delta'
) }}

with daily_engagement as (
    select
        fvs.user_id,
        fvs.session_date as engagement_date,
        -- Aggregate total viewing time at the user-day grain.
        sum(fvs.watch_minutes) as total_watch_minutes,
        -- Count sessions to measure visit frequency.
        count(*) as session_count,
        -- Count unique titles to measure breadth of consumption.
        count(distinct fvs.content_id) as distinct_titles_watched,
        -- Average completion_pct to capture depth of engagement.
        avg(fvs.completion_pct) as average_completion
    from {{ ref('fact_viewing_sessions') }} fvs
    group by 1, 2
),

rolling_metrics as (
    select
        user_id,
        engagement_date,
        total_watch_minutes,
        session_count,
        distinct_titles_watched,
        average_completion,
        -- Calculate the current 7-day average watch minutes including the current day.
        avg(total_watch_minutes) over (
            partition by user_id
            order by engagement_date
            rows between 6 preceding and current row
        ) as rolling_7d_avg_watch_minutes,
        -- Calculate the prior 7-day average from the week immediately before the current window.
        avg(total_watch_minutes) over (
            partition by user_id
            order by engagement_date
            rows between 13 preceding and 7 preceding
        ) as previous_7d_avg_watch_minutes
    from daily_engagement
)

select
    user_id,
    engagement_date,
    total_watch_minutes,
    session_count,
    distinct_titles_watched,
    average_completion,
    rolling_7d_avg_watch_minutes,
    previous_7d_avg_watch_minutes,
    -- Express engagement deterioration as a percentage drop versus the prior week.
    case
        when previous_7d_avg_watch_minutes is null or previous_7d_avg_watch_minutes = 0 then null
        else round(
            ((previous_7d_avg_watch_minutes - rolling_7d_avg_watch_minutes) / previous_7d_avg_watch_minutes) * 100,
            2
        )
    end as engagement_drop_pct
from rolling_metrics
