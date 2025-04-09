/**
 * # Terraform State Backup Module - Variables
 *
 * Variables for configuring the Terraform state backup module.
 */

# ---------------------------------------------------------------------------------------------------------------------
# REQUIRED PARAMETERS
# ---------------------------------------------------------------------------------------------------------------------

variable "resource_group_name" {
  description = "The name of the resource group in which to create all resources"
  type        = string
}

variable "location" {
  description = "The Azure region where the primary resources should be created"
  type        = string
}

variable "backup_location" {
  description = "The Azure region where backup resources should be created (should be different from primary location)"
  type        = string
}

variable "source_storage_account_name" {
  description = "The name of the storage account containing the Terraform state to back up"
  type        = string
}

variable "source_storage_account_id" {
  description = "The resource ID of the storage account containing the Terraform state to back up"
  type        = string
}

variable "source_container_name" {
  description = "The name of the container in the source storage account containing the Terraform state to back up"
  type        = string
  default     = "terraform-state"
}

variable "backup_storage_account_name" {
  description = "The name of the storage account for storing backups"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.backup_storage_account_name))
    error_message = "The backup storage account name must be between 3 and 24 characters, lowercase letters and numbers only."
  }
}

variable "log_analytics_workspace_id" {
  description = "The resource ID of the Log Analytics workspace for monitoring"
  type        = string
}

variable "alert_email" {
  description = "Email address to send alerts to"
  type        = string
}

# ---------------------------------------------------------------------------------------------------------------------
# OPTIONAL PARAMETERS
# ---------------------------------------------------------------------------------------------------------------------

variable "environment" {
  description = "Environment name for resource naming and tagging (dev, test, prod, etc.)"
  type        = string
  default     = "dev"
}

variable "region_abbv" {
  description = "Abbreviation for region to use in resource naming"
  type        = string
  default     = "eus"
}

variable "backup_frequency" {
  description = "Frequency of backups (daily, weekly, monthly)"
  type        = string
  default     = "daily"
  validation {
    condition     = contains(["daily", "weekly", "monthly"], var.backup_frequency)
    error_message = "Backup frequency must be daily, weekly, or monthly."
  }
}

variable "daily_backup_time" {
  description = "Hour of the day to run daily backups (0-23)"
  type        = number
  default     = 1
  validation {
    condition     = var.daily_backup_time >= 0 && var.daily_backup_time <= 23
    error_message = "Daily backup time must be between 0 and 23."
  }
}

variable "weekly_backup_day" {
  description = "Day of the week to run weekly backups (0-6, where 0 is Sunday)"
  type        = number
  default     = 0
  validation {
    condition     = var.weekly_backup_day >= 0 && var.weekly_backup_day <= 6
    error_message = "Weekly backup day must be between 0 and 6."
  }
}

variable "monthly_backup_day" {
  description = "Day of the month to run monthly backups (1-28)"
  type        = number
  default     = 1
  validation {
    condition     = var.monthly_backup_day >= 1 && var.monthly_backup_day <= 28
    error_message = "Monthly backup day must be between 1 and 28."
  }
}

variable "backup_retention_days" {
  description = "Number of days to retain backup files"
  type        = number
  default     = 30
  validation {
    condition     = var.backup_retention_days >= 7
    error_message = "Backup retention days must be at least 7."
  }
}

variable "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access the backup storage account"
  type        = list(string)
  default     = []
}

variable "allowed_subnet_ids" {
  description = "List of subnet IDs allowed to access the backup storage account"
  type        = list(string)
  default     = []
}

variable "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  type        = string
  default     = null
}

variable "application_insights_key" {
  description = "Instrumentation key for Application Insights"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
} 