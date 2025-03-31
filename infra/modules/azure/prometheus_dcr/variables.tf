/**
 * Variables for the Prometheus DCR module.
 */

variable "name" {
  description = "Optional base name for the DCR (e.g., 'dcr-prometheus'). Defaults will be generated if null."
  type        = string
  default     = null
}

variable "dce_name" {
  description = "Optional name for the Data Collection Endpoint (DCE). Defaults will be generated if null."
  type        = string
  default     = null
}

variable "resource_group_name" {
  description = "The name of the resource group to deploy the DCR and DCE in."
  type        = string
}

variable "location" {
  description = "The Azure region where the DCR and DCE will be deployed."
  type        = string
}

variable "monitor_workspace_id" {
  description = "The resource ID of the Azure Monitor Workspace to send metrics to."
  type        = string
}

variable "tags" {
  description = "A map of tags to apply to the DCR and DCE."
  type        = map(string)
  default     = {}
} 