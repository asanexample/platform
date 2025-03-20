variable "resource_group_name" {
  description = "The name of the resource group in which to create the private DNS zones"
  type        = string
}

variable "private_dns_zones" {
  description = "Map of private DNS zones to create"
  type = map(object({
    name                      = string
    vnet_id                   = string
    vnet_resource_group_name  = string
    registration_enabled      = bool
    virtual_network_link_name = string
  }))
}

variable "tags" {
  description = "A mapping of tags to assign to the resources"
  type        = map(string)
  default     = {}
} 