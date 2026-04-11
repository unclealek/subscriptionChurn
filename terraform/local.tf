locals {
  pipeline_job_name = "${var.project_name}-${var.environment}-pipeline"
  python_env_key    = "subscription-churn-python"

  workspace_project_path = trimsuffix(var.workspace_project_path, "/")

  generator_environment_variables = {
    SEED_DIR       = "${local.workspace_project_path}/seeds"
    VOLUME_CATALOG = var.volume_catalog
    VOLUME_SCHEMA  = var.volume_schema
    VOLUME_NAME    = var.volume_name
  }
}
