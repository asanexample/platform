variable "create" {
  description = "Whether to deploy Backstage"
  type        = bool
  default     = true
}

variable "helm_release_name" {
  description = "Helm release name"
  type        = string
  default     = "backstage"
}

variable "helm_repository" {
  description = "Helm chart repository"
  type        = string
  default     = "https://backstage.github.io/charts"
}

variable "helm_chart" {
  description = "Helm chart name"
  type        = string
  default     = "backstage"
}

variable "helm_chart_version" {
  description = "Helm chart version (pinned in _versions.hcl)"
  type        = string
}

variable "namespace" {
  description = "Namespace for Backstage"
  type        = string
  default     = "backstage"
}

variable "helm_timeout" {
  description = "Helm release timeout (seconds)"
  type        = number
  default     = 600
}

variable "helm_wait" {
  description = "Wait for the release to become ready. Default false: the DB Cluster provisions async, so we verify pod health out of band rather than risk a wait timeout."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Image (built + signed by the asanexample/backstage repo CI -> platform/backstage ECR)
# ---------------------------------------------------------------------------

variable "image_registry" {
  description = "ECR registry host for the Backstage image"
  type        = string
  default     = "829808296602.dkr.ecr.us-east-1.amazonaws.com"
}

variable "image_repository" {
  description = "ECR repository for the Backstage image"
  type        = string
  default     = "platform/backstage"
}

variable "image_tag" {
  description = "Backstage image tag (the asanexample/backstage commit SHA)"
  type        = string
}

variable "replica_count" {
  description = "Backstage backend replicas"
  type        = number
  default     = 1
}

# ---------------------------------------------------------------------------
# Database (configurable: in-cluster CloudNativePG for dev, RDS for prod — ADR-051)
# ---------------------------------------------------------------------------

variable "database" {
  description = "Backstage database. mode = in-cluster (CloudNativePG) | rds. For in-cluster, instances/storage_size size the CNPG Cluster."
  type = object({
    mode         = optional(string, "in-cluster")
    instances    = optional(number, 1)
    storage_size = optional(string, "5Gi")
  })
  default = {}

  validation {
    condition     = contains(["in-cluster", "rds"], var.database.mode)
    error_message = "database.mode must be 'in-cluster' or 'rds'."
  }
}

variable "db_cluster_name" {
  description = "Name of the CloudNativePG Cluster (in-cluster mode). CNPG creates <name>-rw Service + <name>-app Secret."
  type        = string
  default     = "backstage-db"
}

variable "rds_host" {
  description = "RDS Postgres endpoint host (rds mode)."
  type        = string
  default     = ""
}

variable "rds_secret_name" {
  description = "Name of the K8s Secret (ExternalSecret-synced) holding username/password for RDS (rds mode)."
  type        = string
  default     = ""
}

variable "resources" {
  description = "Backstage backend container resource requests/limits"
  type = object({
    requests = optional(map(string), { cpu = "250m", memory = "512Mi" })
    limits   = optional(map(string), { cpu = "1", memory = "1Gi" })
  })
  default = {}
}

# ---------------------------------------------------------------------------
# OIDC SSO (Phase 2.1 — auth via the Dex broker, ADR-051)
# ---------------------------------------------------------------------------

variable "enable_oidc" {
  description = "Wire OIDC SSO: sync the Dex client secret (platform/backstage/oidc) into the namespace and inject it as OIDC_CLIENT_SECRET. The image's app-config.production.yaml configures the provider."
  type        = bool
  default     = true
}

variable "oidc_secret_name" {
  description = "Secrets Manager path holding the shared Dex OIDC client secret (created by the dex module)."
  type        = string
  default     = "platform/backstage/oidc"
}

variable "oidc_secret_key" {
  description = "Key/property within the OIDC Secrets Manager secret (and the synced K8s Secret)."
  type        = string
  default     = "client-secret"
}

variable "secret_store_name" {
  description = "Name of the ClusterSecretStore (External Secrets) to read Secrets Manager."
  type        = string
  default     = "aws-secrets-manager"
}

# ---------------------------------------------------------------------------
# GitHub catalog discovery (Phase 2.2 — read-only GitHub App, ADR-051)
# ---------------------------------------------------------------------------

variable "enable_github_discovery" {
  description = "Sync the read-only GitHub App credential (github_app_secret_name) into the namespace and inject it as GITHUB_APP_ID/GITHUB_APP_PRIVATE_KEY. The image's app-config wires integrations.github.apps + catalog.providers.github."
  type        = bool
  default     = true
}

variable "github_app_secret_name" {
  description = "Secrets Manager path holding the GitHub App credential as JSON {appId, privateKey}. Created manually; see docs/runbooks/backstage-github-app.md."
  type        = string
  default     = "platform/backstage/github-app"
}

variable "host_aliases" {
  description = <<-DESC
    Pod /etc/hosts entries. Used for split-horizon resolution of the OIDC issuer hostname
    (sso.aws.refplat.org) to the in-cluster Cilium gateway ClusterIP, so the backend's OIDC
    discovery + token exchange with Dex stay IN-CLUSTER (TLS still validates via the wildcard
    cert at the gateway) instead of depending on public DNS resolving the internal-NLB hairpin.
  DESC
  type = list(object({
    ip        = string
    hostnames = list(string)
  }))
  default = []
}

variable "tags" {
  description = "Tags (rendered as pod labels)"
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# Kubernetes plugin (Phase 2.4a) — read-only live cluster view
# ---------------------------------------------------------------------------

variable "enable_kubernetes_plugin" {
  description = "Enable the Backstage Kubernetes plugin: create the EKS Pod Identity reader role + this-cluster access entry and inject the kubernetes app-config layer."
  type        = bool
  default     = false
}

variable "cluster_name" {
  description = "This (platform) EKS cluster name — for the Pod Identity association and the cluster-View access entry."
  type        = string
  default     = ""
}

variable "remote_cluster_role_arns" {
  description = "Cross-account read-only Backstage role ARNs the reader role may assume (e.g. the preprod Backstage role) for the Kubernetes plugin."
  type        = list(string)
  default     = []
}

variable "kubernetes_clusters" {
  description = "Clusters surfaced by the Kubernetes plugin (rendered into the kubernetes app-config). authProvider is always aws; set assume_role for cross-account clusters."
  type = list(object({
    name        = string
    url         = string
    ca_data     = string
    region      = optional(string, "us-east-1")
    assume_role = optional(string)
  }))
  default = []
}
