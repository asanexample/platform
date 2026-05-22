variable "create" {
  description = "Controls whether resources should be created"
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "Name of the EKS/AKS cluster (used for Connector naming)"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# OAuth
# ---------------------------------------------------------------------------

variable "oauth_client_id" {
  description = "Tailscale OAuth client ID (not needed when using generated oauth_override.tf)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "oauth_client_secret" {
  description = "Tailscale OAuth client secret (not needed when using generated oauth_override.tf)"
  type        = string
  sensitive   = true
  default     = ""
}

# ---------------------------------------------------------------------------
# Subnet routing
# ---------------------------------------------------------------------------

variable "advertise_routes" {
  description = "CIDR ranges to advertise via the Tailscale subnet router"
  type        = list(string)
  default     = []
}

variable "connector_hostname" {
  description = "Hostname suffix for the Tailscale Connector device"
  type        = string
  default     = "subnet-router"
}

# ---------------------------------------------------------------------------
# Helm
# ---------------------------------------------------------------------------

variable "helm_release_name" {
  description = "Name of the Helm release"
  type        = string
  default     = "tailscale-operator"
}

variable "helm_repository" {
  description = "Repository URL for the Tailscale operator Helm chart"
  type        = string
  default     = "https://pkgs.tailscale.com/helmcharts"
}

variable "helm_chart" {
  description = "Name of the Helm chart"
  type        = string
  default     = "tailscale-operator"
}

variable "helm_chart_version" {
  description = "Version of the Tailscale operator Helm chart"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace to install the Tailscale operator into"
  type        = string
  default     = "tailscale-system"
}

variable "helm_timeout" {
  description = "Timeout for Helm operations in seconds"
  type        = number
  default     = 600
}

variable "helm_wait" {
  description = "Whether to wait for Helm release to complete"
  type        = bool
  default     = true
}
