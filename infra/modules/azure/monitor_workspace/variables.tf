/**
 * Variables for the Azure Monitor Workspace module.
 */

variable "name" {
  description = "The name of the Azure Monitor Workspace."
  type        = string
}

variable "resource_group_name" {
  description = "The name of the resource group to deploy the Azure Monitor Workspace in."
  type        = string
}

variable "location" {
  description = "The Azure region where the Azure Monitor Workspace will be deployed."
  type        = string
}

variable "tags" {
  description = "A map of tags to apply to the Azure Monitor Workspace."
  type        = map(string)
  default     = {}
} 