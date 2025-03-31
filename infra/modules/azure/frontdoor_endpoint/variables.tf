variable "enabled" {
  description = "Controls whether the Front Door endpoint resources are deployed"
  type        = bool
  default     = true
}

variable "profile_id" {
  description = "The ID of the Front Door profile. If provided, profile_name and profile_resource_group_name are not required."
  type        = string
  default     = null
}

variable "profile_name" {
  description = "The name of the Front Door profile. Required if profile_id is not provided."
  type        = string
  default     = null
  validation {
    condition     = var.profile_name == null || can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{1,78}[a-zA-Z0-9]$", var.profile_name))
    error_message = "If provided, profile_name must be between 3 and 80 characters long, can contain alphanumerics and hyphens, must start and end with alphanumeric."
  }
}

variable "profile_resource_group_name" {
  description = "The name of the resource group containing the Front Door profile. Required if profile_id is not provided."
  type        = string
  default     = null
  validation {
    condition     = var.profile_resource_group_name == null || can(regex("^[a-zA-Z0-9-_().]{1,90}$", var.profile_resource_group_name))
    error_message = "If provided, resource group names must be between 1 and 90 characters and can only include alphanumeric, underscore, parentheses, hyphen, and period."
  }
}

variable "endpoint_name" {
  description = "The name of the Front Door endpoint"
  type        = string
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{1,78}[a-zA-Z0-9]$", var.endpoint_name))
    error_message = "Endpoint name must be between 3 and 80 characters long, can contain alphanumerics and hyphens, must start and end with alphanumeric."
  }
}

variable "origin_group_name" {
  description = "The name of the origin group"
  type        = string
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{1,78}[a-zA-Z0-9]$", var.origin_group_name))
    error_message = "Origin group name must be between 3 and 80 characters long, can contain alphanumerics and hyphens, must start and end with alphanumeric."
  }
}

variable "load_balancing_enabled" {
  description = "Whether to enable custom load balancing settings"
  type        = bool
  default     = false
}

variable "load_balancing_settings" {
  description = "Load balancing settings for the origin group"
  type = object({
    additional_latency_in_milliseconds = optional(number)
    sample_size                        = optional(number)
    successful_samples_required        = optional(number)
  })
  default = {
    additional_latency_in_milliseconds = null
    sample_size                        = null
    successful_samples_required        = null
  }
  validation {
    condition = var.load_balancing_settings.additional_latency_in_milliseconds == null || (
      var.load_balancing_settings.additional_latency_in_milliseconds >= 0 &&
      var.load_balancing_settings.additional_latency_in_milliseconds <= 1000
    )
    error_message = "If provided, additional latency must be between 0 and 1000 milliseconds."
  }
  validation {
    condition = var.load_balancing_settings.sample_size == null || (
      var.load_balancing_settings.sample_size >= 0 &&
      var.load_balancing_settings.sample_size <= 255
    )
    error_message = "If provided, sample size must be between 0 and 255."
  }
  validation {
    condition = var.load_balancing_settings.successful_samples_required == null || (
      var.load_balancing_settings.successful_samples_required >= 0 &&
      var.load_balancing_settings.successful_samples_required <= 255
    )
    error_message = "If provided, successful samples required must be between 0 and 255."
  }
}

variable "health_probe_enabled" {
  description = "Whether to enable health probe"
  type        = bool
  default     = false
}

variable "health_probe_settings" {
  description = "Health probe settings for the origin group"
  type = object({
    protocol            = optional(string, "Http")
    interval_in_seconds = optional(number, 120)
    path                = optional(string, "/")
    request_type        = optional(string, "HEAD")
  })
  default = {
    protocol            = "Http"
    interval_in_seconds = 120
    path                = "/"
    request_type        = "HEAD"
  }
  validation {
    condition     = contains(["Http", "Https"], var.health_probe_settings.protocol)
    error_message = "Protocol must be either Http or Https."
  }
  validation {
    condition     = var.health_probe_settings.interval_in_seconds >= 5 && var.health_probe_settings.interval_in_seconds <= 255
    error_message = "Interval must be between 5 and 255 seconds."
  }
  validation {
    condition     = startswith(var.health_probe_settings.path, "/")
    error_message = "Path must start with a slash (/)."
  }
  validation {
    condition     = contains(["GET", "HEAD"], var.health_probe_settings.request_type)
    error_message = "Request type must be either GET or HEAD."
  }
}

variable "tags" {
  description = "A mapping of tags to assign to resources"
  type        = map(string)
  default     = {}
} 