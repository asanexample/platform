variable "create" {
  description = "Whether to create resources in this module"
  type        = bool
  default     = true
}

variable "name" {
  description = "Name prefix for all resources and the Tailscale device hostname"
  type        = string
}

variable "region" {
  description = "AWS region — used by the instance to fetch its auth secret at boot"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID to place the subnet router in"
  type        = string
}

variable "subnet_id" {
  description = "Private subnet ID for the router instance. MUST have NAT egress so the box can reach Tailscale's coordination/DERP servers and install packages at boot."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type (Graviton/arm64 — the AMI is arm64)"
  type        = string
  default     = "t4g.nano"
}

variable "advertise_routes" {
  description = "CIDR blocks advertised into the tailnet as subnet routes (e.g. the VPC CIDR). For routes to auto-approve, each must be covered by the tailnet autoApprovers for one of advertise_tags."
  type        = list(string)

  validation {
    condition     = length(var.advertise_routes) > 0
    error_message = "advertise_routes must contain at least one CIDR block."
  }
}

variable "advertise_tags" {
  description = "Tailscale ACL tags advertised for the router device. Must be owned by the auth credential's OAuth client and present in the tailnet autoApprovers for the advertised routes to self-approve."
  type        = list(string)
  default     = ["tag:k8s-operator"]
}

variable "auth_secret_id" {
  description = "Secrets Manager secret ID holding the Tailscale OAuth client credential as JSON ({clientId, clientSecret}). The instance reads clientSecret at boot and uses it as its auth key."
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
