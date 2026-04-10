# Subscription Churn Analytics

This project builds a dbt analytics pipeline for subscription churn analysis on top of seeded reference data and generated streaming behavior.

## Project Scope

The pipeline is organized in two modeling layers:

- `silver`: cleaned and standardized operational tables
- `gold`: business-facing fact tables and analytical marts

The current ground truth for plans and users comes from the seed files:

- `seeds/users_seed.csv`
- `seeds/subscription_plans.csv`
- `seeds/devices.csv`
- `seeds/genres.csv`
- `seeds/content_catalog.csv`

Silver models are expected to follow that seed contract.

## Seed Data

Reference entities are stored as CSV seeds:

- `users_seed`
- `subscription_plans`
- `devices`
- `genres`
- `content_catalog`

Generated event-style inputs live under `generated/`:

- viewing sessions
- subscription events

## Silver Models

The silver layer standardizes raw and seed-backed data into reusable analytical tables.

- `users`
  - standardizes user attributes
  - derives canonical initial subscription status
  - enriches users with initial plan metadata
- `subs_plan`
  - standardizes plan labels and types
  - adds paid, trial, cancelled, and rank flags
- `subs_events`
  - standardizes subscription statuses
  - derives `plan_change_type`
  - aligns `price` and `currency` to `new_plan_id`
- `view_sess`
  - standardizes session timestamps and booleans
  - derives session duration, completion buckets, and quality flags
- `content`
  - standardizes content metadata
  - derives content age and runtime buckets
- `user_devices`
  - standardizes device and OS metadata
  - derives device families and app major version
- `movie_genres`
  - standardizes genre labels
  - identifies top-level genres

## Gold Models

### Fact Tables

- `fact_subscription_events`
  - joins subscription events to users and plans
- `fact_viewing_sessions`
  - joins viewing sessions to users, devices, content, and latest subscription state
- `fact_daily_user_engagement`
  - one row per user per day
  - includes total watch minutes, session count, distinct titles watched, average completion, current 7-day average, previous 7-day average, and engagement drop percentage

### Analytical Marts

- `mart_churn_signals`
  - flags users when engagement drops materially
  - includes current and previous 7-day averages, engagement drop percentage, churn flag, and risk band
- `mart_subscription_attribution`
  - attributes subscription events to viewing behavior in the prior 24 hours
  - includes last watched title, most watched title, most watched genre, total watch minutes, title count, and attribution method
- `mart_user_clv`
  - combines subscription history, engagement, and churn risk
  - includes first subscription date, current plan, tenure, revenue to date, active days in the last 30 days, churn flag, and estimated CLV

## Build Order

Recommended execution order:

1. `dbt seed`
2. `dbt run --select models/silver`
3. `dbt run --select fact_subscription_events fact_viewing_sessions`
4. `dbt run --select fact_daily_user_engagement mart_churn_signals mart_subscription_attribution mart_user_clv`
5. `dbt test`

## Common Commands

Run the full project:

```bash
dbt run
dbt test
```

Build only the silver layer:

```bash
dbt run --select models/silver
```

Build only the gold layer:

```bash
dbt run --select models/gold
```

Build the churn-related outputs:

```bash
dbt run --select fact_daily_user_engagement mart_churn_signals mart_user_clv
```

Build the attribution output:

```bash
dbt run --select mart_subscription_attribution
```

## Notes

- The project uses Databricks with Delta tables.
- Transformation comments are included directly in the SQL models for derived fields.
- Current gold engagement logic only produces rows for dates with at least one viewing session; it does not yet generate zero-activity dates.
