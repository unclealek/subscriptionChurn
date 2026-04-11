variable "databricks_host" {
  type        = string
  description = "Databricks workspace URL"
}

variable "databricks_token" {
  type        = string
  description = "Databricks personal access token or service principal token"
  sensitive   = true
}

variable "project_name" {
  type        = string
  description = "Project name used in Databricks resource names"
  default     = "subscription-churn"
}

variable "environment" {
  type        = string
  description = "Deployment environment name, for example dev or prod"

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be either dev or prod."
  }
}

variable "workspace_project_path" {
  type        = string
  description = "Databricks workspace path containing the operational Python scripts"
  default     = "/Workspace/Users/kelvin.aliche@gmail.com/transformation"
}

variable "git_url" {
  type        = string
  description = "Git URL containing the dbt project"
  default     = "https://github.com/unclealek/subscriptionChurn.git"
}

variable "git_provider" {
  type        = string
  description = "Databricks Git provider name"
  default     = "gitHub"
}

variable "git_branch" {
  type        = string
  description = "Git branch used by Databricks dbt tasks"
}

variable "subscription_events_script_path" {
  type        = string
  description = "Databricks workspace path to the script that generates subscription event JSON files"
  default     = "/Workspace/Users/kelvin.aliche@gmail.com/transformation/generate_subscription_events.py"
}

variable "viewing_sessions_script_path" {
  type        = string
  description = "Databricks workspace path to the script that generates viewing session JSON files"
  default     = "/Workspace/Users/kelvin.aliche@gmail.com/transformation/generate_viewing_sessions.py"
}

variable "bronze_loader_script_path" {
  type        = string
  description = "Databricks workspace path to the script that loads generated JSON into bronze Delta tables"
  default     = "/Workspace/Users/kelvin.aliche@gmail.com/transformation/createTable.py"
}

variable "warehouse_id" {
  type        = string
  description = "Existing Databricks SQL warehouse ID used by dbt tasks"
}

variable "dbt_catalog" {
  type        = string
  description = "Catalog used by dbt for this environment"
  default     = "transform"
}

variable "dbt_schema" {
  type        = string
  description = "Default schema used by dbt for this environment"
  default     = "dbt_silver"
}

variable "dbt_target" {
  type        = string
  description = "dbt target name used by local and CI dbt commands"
}

variable "volume_catalog" {
  type        = string
  description = "Unity Catalog catalog that owns the raw data volume"
  default     = "transform"
}

variable "volume_schema" {
  type        = string
  description = "Unity Catalog schema that owns the raw data volume"
  default     = "movierecommendation"
}

variable "volume_name" {
  type        = string
  description = "Unity Catalog volume where generated JSON files are written"
  default     = "raw_data"
}

variable "job_timezone" {
  type        = string
  description = "Timezone for the job schedule"
  default     = "Europe/Helsinki"
}

variable "job_cron_expression" {
  type        = string
  description = "Quartz cron expression for the scheduled Databricks Workflow"
  default     = "0 0 9 * * ?"
}

variable "job_pause_status" {
  type        = string
  description = "Whether the Databricks Workflow schedule is paused"
  default     = "UNPAUSED"

  validation {
    condition     = contains(["PAUSED", "UNPAUSED"], var.job_pause_status)
    error_message = "job_pause_status must be PAUSED or UNPAUSED."
  }
}
