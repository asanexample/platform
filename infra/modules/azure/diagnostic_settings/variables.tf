variable "create" {
  description = "Whether to create resources in this module"
  type        = bool
  default     = true
}

variable "diagnostic_settings" {
  description = "Map of diagnostic settings to create. Each routes logs/metrics from a target resource to Log Analytics."
  type = map(object({
    target_resource_id         = string
    log_analytics_workspace_id = string

    enabled_log_categories = optional(list(string), [])

    log_category_groups = optional(list(string), [])

    metric_categories = optional(list(string), [])

    log_analytics_destination_type = optional(string, null)
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.diagnostic_settings :
      length(v.target_resource_id) > 0 && length(v.log_analytics_workspace_id) > 0
    ])
    error_message = "Both target_resource_id and log_analytics_workspace_id are required for each diagnostic setting."
  }
}

variable "tags" {
  description = "Tags (not applied to diagnostic settings directly, reserved for future use)"
  type        = map(string)
  default     = {}
}
