Welcome to your new dbt project!

### Using the starter project

Try running the following commands:
- dbt run
- dbt test


### Resources:
- Learn more about dbt [in the docs](https://docs.getdbt.com/docs/introduction)
- Check out [Discourse](https://discourse.getdbt.com/) for commonly asked questions and answers
- Join the [chat](https://community.getdbt.com/) on Slack for live discussions and support
- Find [dbt events](https://events.getdbt.com) near you
- Check out [the blog](https://blog.getdbt.com/) for the latest news on dbt's development and best practices


### Subscription Churn Analysis
## Track Steps
- cd to project directory
- dbt init
- create schema and catalog in Databricks
- create git repo
- push to github
- Step 1

Create reference CSVs:

users
devices
genres
subscription_plans
content_catalog

Step 2

Create Python generator for viewing sessions

Step 3

Create Python generator for subscription events

Step 4

Drop files into raw volumne

Step 5

Load into Bronze tables into schema/table
Step 6

Build Silver models in dbt:

clean users
clean content
clean viewing sessions
clean subscription events
Step 7

Build Gold models:

fact_viewing_sessions
fact_subscription_events
dim_users_scd2
dim_content
dim_genre
dim_subscription_plans
Step 8

Build marts:

daily engagement
attribution
churn
CLV
