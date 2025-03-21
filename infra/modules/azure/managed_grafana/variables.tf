variable "name" {
  description = "The name of the Azure Managed Grafana instance"
  type        = string
}

variable "resource_group_name" {
  description = "The name of the resource group in which to create the Grafana instance"
  type        = string
}

variable "location" {
  description = "The Azure location where the Grafana instance should be created"
  type        = string
}

variable "grafana_major_version" {
  description = "The major version of Grafana to deploy"
  type        = string
  default     = "10" # Latest major version as of now
}

variable "api_key_enabled" {
  description = "Enable the API key mechanism in Grafana"
  type        = bool
  default     = true
}

variable "deterministic_outbound_ip_enabled" {
  description = "Whether to enable deterministic outbound IPs for the Grafana instance"
  type        = bool
  default     = true
}

variable "public_network_access_enabled" {
  description = "Whether to enable public network access for the Grafana instance"
  type        = bool
  default     = true
}

variable "zone_redundancy_enabled" {
  description = "Whether to enable zone redundancy for the Grafana instance"
  type        = bool
  default     = true
}

variable "prometheus_workspace_id" {
  description = "The resource ID of the Azure Monitor workspace (Managed Prometheus)"
  type        = string
}

variable "admin_group_object_ids" {
  description = "A list of Azure AD group object IDs to be assigned the Grafana Admin role"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "A mapping of tags to assign to the resource"
  type        = map(string)
  default     = {}
} 