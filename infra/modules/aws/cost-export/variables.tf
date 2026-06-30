variable "create" {
  description = "Whether to create the cost-export resources."
  type        = bool
  default     = true
}

variable "name" {
  description = "Base name/prefix for resources (S3 bucket prefix, Glue crawler, Athena workgroup, IAM roles)."
  type        = string
  default     = "platform-cost-export"
}

variable "cur_report_name" {
  description = "Name of the legacy Cost & Usage Report."
  type        = string
  default     = "platform-cur"
}

variable "s3_prefix" {
  description = "S3 key prefix under which the CUR is delivered."
  type        = string
  default     = "cur"
}

variable "glue_database_name" {
  description = "Glue Data Catalog database the CUR table is crawled into."
  type        = string
  default     = "platform_cur"
}

variable "crawler_schedule" {
  description = "Cron schedule for the Glue crawler (UTC). Daily by default — CUR refreshes a few times a day, daily catches new partitions cheaply."
  type        = string
  default     = "cron(0 3 * * ? *)"
}

variable "athena_results_prefix" {
  description = "S3 key prefix for Athena query results (lifecycle-expired)."
  type        = string
  default     = "athena-results"
}

variable "athena_results_retention_days" {
  description = "Days to retain Athena query results before expiry."
  type        = number
  default     = 14
}

variable "cur_noncurrent_retention_days" {
  description = "Days to retain noncurrent CUR object versions (the report is OVERWRITE, so old versions are churn)."
  type        = number
  default     = 30
}

variable "reader_trusted_principal_arns" {
  description = "Principal ARNs (in the consumer account, e.g. the platform OpenCost pod-identity role or that account's root) allowed to assume the cross-account cost_reader role. Empty disables the role (the AWS infra still applies)."
  type        = list(string)
  default     = []
}

variable "cost_reader_role_name" {
  description = "Name of the cross-account read role OpenCost assumes."
  type        = string
  default     = "platform-cost-reader"
}

variable "force_destroy" {
  description = "Allow destroying the S3 bucket / Athena workgroup with contents (true only for throwaway/test)."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to taggable resources."
  type        = map(string)
  default     = {}
}
