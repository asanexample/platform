variable "create" {
  description = "Controls whether resources should be created"
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "EKS cluster name the associations are created for"
  type        = string
}

variable "associations" {
  description = <<-EOT
    Map of association key -> binding. Each binds a (namespace, service_account) on the cluster to an IAM
    role; pods running as that ServiceAccount receive the role's credentials via the EKS Pod Identity
    agent. Team-agnostic: the per-service map is built at the terragrunt unit from the git-native
    Team/Product registries (gitops/teams, gitops/products), not teams.hcl (retired, ADR-063/067).
  EOT
  type = map(object({
    namespace       = string
    service_account = string
    role_arn        = string
  }))
  default = {}
}

variable "tags" {
  description = "Tags applied to the associations"
  type        = map(string)
  default     = {}
}
