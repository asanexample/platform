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
  description = "Wire OIDC SSO: sync the Keycloak `backstage` client secret into the namespace as OIDC_CLIENT_SECRET + generate the Backstage session-signing secret (AUTH_SESSION_SECRET). The image's app-config.production.yaml configures the direct-Keycloak `oidc` provider."
  type        = bool
  default     = true
}

variable "oidc_secret_name" {
  description = "Secrets Manager path holding the Keycloak OIDC client secret (the `backstage` confidential client, created by keycloak-config)."
  type        = string
  default     = "platform/keycloak/backstage-oidc"
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

# ---------------------------------------------------------------------------
# Scaffolder GitHub write App (Phase 3 — ADR-062 §5, BACK self-service)
# ---------------------------------------------------------------------------

variable "enable_scaffolder" {
  description = "Sync the scaffolder's GitHub WRITE App credential (scaffolder_github_app_secret_name) into the namespace and inject it as SCAFFOLDER_GITHUB_APP_ID/SCAFFOLDER_GITHUB_APP_PRIVATE_KEY. The image's app-config wires it as the second integrations.github.apps entry (the App is installed on asanexample/platform only). See docs/runbooks/backstage-scaffolder-github-app.md."
  type        = bool
  default     = false
}

variable "scaffolder_github_app_secret_name" {
  description = "Secrets Manager path holding the scaffolder GitHub write App credential as JSON {appId, privateKey}. Created manually; see docs/runbooks/backstage-scaffolder-github-app.md."
  type        = string
  default     = "platform/backstage/scaffolder-github-app"
}

variable "oidc_gateway_alias_host" {
  description = <<-DESC
    Hostname to pin (via /etc/hosts) to the in-cluster Cilium gateway ClusterIP — the OIDC issuer host
    (keycloak.aws.refplat.org). The backend's OIDC discovery + token exchange then hit the gateway's Envoy
    directly instead of the public name's internal-NLB hairpin (which is flaky), while TLS still validates
    (wildcard cert at the gateway). The ClusterIP is looked up dynamically from the gateway Service — NOT
    hardcoded — so it self-corrects on every apply if the Service is recreated. Empty = no alias.
  DESC
  type        = string
  default     = ""
}

variable "gateway_service_name" {
  description = "Name of the Cilium gateway LoadBalancer Service whose ClusterIP backs oidc_gateway_alias_host."
  type        = string
  default     = "cilium-gateway-platform-gateway"
}

variable "gateway_service_namespace" {
  description = "Namespace of the Cilium gateway Service (the shared Gateway lives in `default`)."
  type        = string
  default     = "default"
}

variable "host_aliases" {
  description = "Extra pod /etc/hosts entries (in addition to the dynamically-resolved oidc_gateway_alias_host)."
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

# ---------------------------------------------------------------------------
# Teardown — robust cluster auth for the destroy-time namespace drain.
# On teardown the namespace hung ~5m in Terminating (deadline exceeded) waiting
# on CNPG-left content (pods/PVCs) after the Cluster CR was gone. A when=destroy
# step deletes + force-clears that content first via scripts/k8s-finalizer-clear.sh.
# ---------------------------------------------------------------------------

variable "region" {
  description = "AWS region of the cluster (for destroy-time namespace drain auth)"
  type        = string
  default     = ""
}

variable "deployer_role_arn" {
  description = "IAM role ARN to assume for the destroy-time namespace drain (the PlatformDeployer)"
  type        = string
  default     = ""
}

variable "finalizer_clear_script" {
  description = "Absolute path to scripts/k8s-finalizer-clear.sh (passed from the unit via get_repo_root())"
  type        = string
  default     = ""
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

# ---------------------------------------------------------------------------
# ArgoCD plugin (Phase 2.4b) — read-only deployment view via the Roadie plugin
# ---------------------------------------------------------------------------

variable "enable_argocd_plugin" {
  description = "Enable the Backstage ArgoCD plugin: inject the argocd app-config (appLocatorMethods/instances) + sync the read-only ArgoCD token into ARGOCD_AUTH_TOKEN."
  type        = bool
  default     = false
}

variable "argocd_instances" {
  description = "ArgoCD instances surfaced by the plugin (rendered into argocd.appLocatorMethods). `url` is the in-cluster API the BACKEND calls (e.g. http://argocd-server.argocd.svc); `frontend_url` is the browser-facing UI used for 'open in ArgoCD' links (e.g. https://argocd.aws.refplat.org). The read-only token is injected via ARGOCD_AUTH_TOKEN."
  type = list(object({
    name         = string
    url          = string
    frontend_url = optional(string)
  }))
  default = []
}

variable "argocd_token_secret_name" {
  description = "Secrets Manager path holding the read-only ArgoCD API token (minted out-of-band against the `backstage` account; see docs/runbooks/backstage-argocd.md)."
  type        = string
  default     = "platform/argocd/backstage-token"
}

variable "argocd_token_secret_key" {
  description = "Key/property within the ArgoCD token Secrets Manager secret (and the synced K8s Secret / env)."
  type        = string
  default     = "token"
}
