locals {
  pipeline_job_name = "${var.project_name}-${var.environment}-pipeline"
  python_env_key    = "subscription-churn-python"

  workspace_project_path = trimsuffix(var.workspace_project_path, "/")
}
