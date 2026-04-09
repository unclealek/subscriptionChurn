variable "databricks_host" {
  type        = string
  description = "Databricks_host"
}

variable "databricks_token" {
  type        = string
  description = "Databricks_token"
  sensitive   = true
}

variable "warehouse_id" {
  type        = string
  description = "Existing Databricks SQL warehouse ID"
}
variable "job_timezone" {
  type        = string
  description = "Timezone for the job schedule"
  default     = "Europe/Helsinki"
}
variable "job_cron_expression" {
  type        = string
  description = "Cron expression for the job schedule"
  default     = "0 0 9 * * ?"
}
