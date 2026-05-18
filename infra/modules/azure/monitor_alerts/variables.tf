variable "create" {
  description = "Whether to create resources in this module"
  type        = bool
  default     = true
}

variable "resource_group_name" {
  description = "The resource group to deploy alert resources into"
  type        = string
}

variable "location" {
  description = "Azure region (used only for resource group reference, alerts are global)"
  type        = string
  default     = "global"
}

variable "workload" {
  description = "Workload identifier for resource naming"
  type        = string

  validation {
    condition     = length(var.workload) >= 1 && length(var.workload) <= 10
    error_message = "Workload must be 1-10 characters."
  }
}

variable "environment" {
  description = "Environment name"
  type        = string

  validation {
    condition     = contains(["dev", "preprod", "prod", "test", "stg", "ops"], var.environment)
    error_message = "Environment must be one of: dev, preprod, prod, test, stg, ops."
  }
}

variable "region_abbv" {
  description = "Abbreviated Azure region name"
  type        = string
}

# --- Action Groups ---

variable "action_groups" {
  description = "Action groups for alert routing"
  type = map(object({
    short_name = string
    enabled    = optional(bool, true)

    email_receivers = optional(list(object({
      name                    = string
      email_address           = string
      use_common_alert_schema = optional(bool, true)
    })), [])

    webhook_receivers = optional(list(object({
      name                    = string
      service_uri             = string
      use_common_alert_schema = optional(bool, true)
    })), [])
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.action_groups : length(v.short_name) <= 12
    ])
    error_message = "Action group short_name must be 12 characters or less."
  }
}

# --- Metric Alerts ---

variable "metric_alerts" {
  description = "Metric-based alert rules"
  type = map(object({
    description       = optional(string, "")
    severity          = optional(number, 2)
    enabled           = optional(bool, true)
    scopes            = list(string)
    frequency         = optional(string, "PT5M")
    window_size       = optional(string, "PT15M")
    action_group_keys = list(string)
    auto_mitigate     = optional(bool, true)

    criteria = list(object({
      metric_namespace = string
      metric_name      = string
      aggregation      = string
      operator         = string
      threshold        = number
      dimension = optional(list(object({
        name     = string
        operator = string
        values   = list(string)
      })), [])
    }))
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.metric_alerts :
      contains([0, 1, 2, 3, 4], v.severity)
    ])
    error_message = "Alert severity must be 0 (Critical), 1 (Error), 2 (Warning), 3 (Informational), or 4 (Verbose)."
  }
}

# --- Activity Log Alerts ---

variable "activity_log_alerts" {
  description = "Activity log alert rules for service health and resource operations"
  type = map(object({
    description       = optional(string, "")
    enabled           = optional(bool, true)
    scopes            = list(string)
    action_group_keys = list(string)

    criteria = object({
      category       = string
      operation_name = optional(string, null)
      level          = optional(string, null)
      status         = optional(string, null)
      resource_type  = optional(string, null)

      service_health = optional(object({
        events    = optional(list(string), ["Incident", "Maintenance"])
        locations = optional(list(string), [])
        services  = optional(list(string), [])
      }), null)
    })
  }))
  default = {}
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
