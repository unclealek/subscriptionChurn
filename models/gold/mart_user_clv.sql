{{ config(
    materialized='table',
    table_format='delta'
) }}

with subscription_events as (
    select * from {{ ref('fact_subscription_events') }}
),

churn_signals as (
    select * from {{ ref('mart_churn_signals') }}
),

latest_churn_signal as (
    select
        user_id,
        current_plan_id,
        current_plan_name,
        current_plan_tier,
        current_subscription_status,
        churn_red_flag,
        risk_band,
        row_number() over (
            partition by user_id
            order by engagement_date desc
        ) as rn
    from churn_signals
),

active_days_last_30 as (
    select
        user_id,
        -- Count distinct recent active days as a simple recency/frequency measure.
        count(distinct session_date) as active_days_last_30_days
    from {{ ref('fact_viewing_sessions') }}
    where session_date >= date_sub(current_date(), 30)
    group by 1
),

user_revenue as (
    select
        user_id,
        -- Take the first paid/trial-related subscription timestamp as the monetization start.
        min(case when new_status in ('trial', 'standard', 'premium') then event_date end) as first_subscription_date,
        -- Sum standardized event prices to get realized revenue to date.
        sum(coalesce(price, 0)) as revenue_to_date
    from subscription_events
    group by 1
)

select
    ur.user_id,
    ur.first_subscription_date,
    lcs.current_plan_id,
    lcs.current_plan_name,
    lcs.current_plan_tier,
    lcs.current_subscription_status,
    -- Calculate tenure in days since the user's first subscription date.
    datediff(current_date(), ur.first_subscription_date) as tenure_days,
    ur.revenue_to_date,
    coalesce(ad.active_days_last_30_days, 0) as active_days_last_30_days,
    lcs.churn_red_flag,
    lcs.risk_band,
    -- Estimate CLV with a simple tenure-adjusted multiplier that penalizes churn risk.
    case
        when ur.first_subscription_date is null then 0
        when lcs.risk_band = 'high' then round(ur.revenue_to_date * 0.8, 2)
        when lcs.risk_band = 'medium' then round(ur.revenue_to_date * 1.0, 2)
        when lcs.risk_band = 'low' then round(ur.revenue_to_date * 1.2, 2)
        when lcs.risk_band = 'stable' then round(ur.revenue_to_date * 1.5, 2)
        else round(ur.revenue_to_date, 2)
    end as estimated_clv
from user_revenue ur
left join latest_churn_signal lcs
    on ur.user_id = lcs.user_id
    and lcs.rn = 1
left join active_days_last_30 ad
    on ur.user_id = ad.user_id
