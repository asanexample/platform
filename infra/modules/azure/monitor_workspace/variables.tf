variable "name" {
  description = "The name of the Azure Monitor workspace"
  type        = string
}

variable "resource_group_name" {
  description = "The name of the resource group in which to create the Azure Monitor workspace"
  type        = string
}

variable "location" {
  description = "The Azure location where the Azure Monitor workspace should be created"
  type        = string
}

variable "tags" {
  description = "A mapping of tags to assign to the resources"
  type        = map(string)
  default     = {}
} 