variable "create" {
  description = "Controls whether resources should be created"
  type        = bool
  default     = true
}

variable "trail_name" {
  description = "Name of the CloudTrail trail"
  type        = string
}

variable "is_multi_region" {
  description = "Whether the trail captures events from all regions"
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "Number of days to retain CloudTrail logs in S3"
  type        = number
  default     = 90
}

variable "force_destroy" {
  description = "Allow S3 bucket to be destroyed even if it contains objects"
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Data Event Selectors
# ---------------------------------------------------------------------------

variable "data_event_selectors" {
  description = "Advanced event selectors for data events"
  type = list(object({
    name          = string
    resource_type = string
    resource_arns = optional(list(string), [])
  }))
  default = []
}

# ---------------------------------------------------------------------------
# CloudWatch Integration
# ---------------------------------------------------------------------------

variable "enable_cloudwatch" {
  description = "Send CloudTrail events to CloudWatch Logs for metric filters and alarms"
  type        = bool
  default     = true
}

variable "cloudwatch_retention_days" {
  description = "CloudWatch log group retention in days"
  type        = number
  default     = 30
}

variable "enable_secrets_alarms" {
  description = "Create CloudWatch metric filters and alarms for Secrets Manager activity"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
