{{ config(
    materialized='table',
    table_format='delta'
) }}

with latest_subscription_state as (
    select
        fse.user_id,
        fse.new_plan_id,
        fse.new_plan_name,
        fse.new_plan_tier,
        fse.new_plan_is_paid,
        fse.new_status,
        fse.event_date,
        row_number() over (
            partition by fse.user_id
            order by fse.event_ts desc, fse.subscription_event_id desc
        ) as rn
    from {{ ref('fact_subscription_events') }} fse
),

current_subscription_state as (
    select
        user_id,
        new_plan_id as current_plan_id,
        new_plan_name as current_plan_name,
        new_plan_tier as current_plan_tier,
        new_plan_is_paid,
        new_status as current_subscription_status,
        event_date as last_subscription_event_date
    from latest_subscription_state
    where rn = 1
),

daily_engagement as (
    select * from {{ ref('fact_daily_user_engagement') }}
)

select
    de.user_id,
    de.engagement_date,
    css.current_plan_id,
    css.current_plan_name,
    css.current_plan_tier,
    css.current_subscription_status,
    css.last_subscription_event_date,
    -- Keep the current 7-day engagement average visible for decisioning.
    de.rolling_7d_avg_watch_minutes as current_7d_avg,
    -- Keep the prior 7-day engagement average visible for comparison.
    de.previous_7d_avg_watch_minutes as previous_7d_avg,
    de.engagement_drop_pct,
    -- Flag paid or trial users whose recent engagement dropped by at least 50%.
    case
        when css.current_subscription_status in ('premium', 'standard', 'trial')
            and coalesce(css.new_plan_is_paid, false) = true
            and de.engagement_drop_pct >= 50 then true
        when css.current_subscription_status = 'trial'
            and de.engagement_drop_pct >= 50 then true
        else false
    end as churn_red_flag,
    -- Translate the numeric drop into an analyst-friendly risk band.
    case
        when de.engagement_drop_pct is null then 'insufficient_history'
        when de.engagement_drop_pct >= 70 then 'high'
        when de.engagement_drop_pct >= 50 then 'medium'
        when de.engagement_drop_pct >= 25 then 'low'
        else 'stable'
    end as risk_band
from daily_engagement de
left join current_subscription_state css
    on de.user_id = css.user_id
