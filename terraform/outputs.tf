output "pipeline_job_id" {
  description = "Databricks Workflow job ID for the subscription churn pipeline"
  value       = databricks_job.subscription_churn_pipeline.id
}

output "pipeline_job_url" {
  description = "Databricks Workflow URL for the subscription churn pipeline"
  value       = databricks_job.subscription_churn_pipeline.url
}
