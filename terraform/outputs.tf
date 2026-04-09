output "generating_job_id" {
  description = "Databricks job ID for the generating data job"
  value       = databricks_job.generating.id
}

output "generating_job_url" {
  description = "Databricks job URL for the generating data job"
  value       = databricks_job.generating.url
}
