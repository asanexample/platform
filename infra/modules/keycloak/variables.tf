variable "create" {
  description = "Whether to deploy Keycloak"
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Helm chart (codecentric/keycloakx — the Quarkus Keycloak distribution, ADR-053)
# ---------------------------------------------------------------------------

variable "helm_release_name" {
  description = "Helm release name"
  type        = string
  default     = "keycloak"
}

variable "helm_repository" {
  description = "Helm chart repository"
  type        = string
  default     = "https://codecentric.github.io/helm-charts"
}

variable "helm_chart" {
  description = "Helm chart name"
  type        = string
  default     = "keycloakx"
}

variable "helm_chart_version" {
  description = "Helm chart version (pinned in _versions.hcl)"
  type        = string
}

variable "namespace" {
  description = "Namespace for Keycloak"
  type        = string
  default     = "keycloak"
}

variable "helm_timeout" {
  description = "Helm release timeout (seconds)"
  type        = number
  default     = 600
}

variable "helm_wait" {
  description = "Wait for the release to become ready. Default false: the admin secret syncs async via External Secrets and the DB must come up first; verify health out of band."
  type        = bool
  default     = false
}

variable "replica_count" {
  description = "Keycloak replicas. 1 for B1 (no clustering). HA (2+) additionally requires Infinispan/JGroups discovery (KC_CACHE=ispn + KUBE_PING) — a follow-up."
  type        = number
  default     = 1
}

# ---------------------------------------------------------------------------
# Image (official quay.io/keycloak/keycloak — pinned to the latest stable tag,
# overriding the chart's appVersion so we run the exact Keycloak release we want)
# ---------------------------------------------------------------------------

variable "image_repository" {
  description = "Keycloak image repository"
  type        = string
  default     = "quay.io/keycloak/keycloak"
}

variable "image_tag" {
  description = "Keycloak image tag (the Keycloak version). Defaults to the latest stable; overrides the chart appVersion."
  type        = string
  default     = "26.6.3"
}

# ---------------------------------------------------------------------------
# Hostname / exposure (behind the Cilium Gateway — TLS terminates there)
# ---------------------------------------------------------------------------

variable "hostname_url" {
  description = "Public base URL Keycloak serves on (KC_HOSTNAME). Behind the shared gateway at keycloak.aws.refplat.org."
  type        = string
  default     = "https://keycloak.aws.refplat.org"
}

# ---------------------------------------------------------------------------
# Admin credential (generated here, stored in Secrets Manager, synced by ESO)
# ---------------------------------------------------------------------------

variable "admin_username" {
  description = "Bootstrap admin username"
  type        = string
  default     = "admin"
}

variable "secret_store_name" {
  description = "Name of the ClusterSecretStore (External Secrets) to read Secrets Manager."
  type        = string
  default     = "aws-secrets-manager"
}

variable "secret_recovery_window_days" {
  description = "Secrets Manager recovery window for the generated admin secret. 0 = force-delete (setup-friendly); raise for prod."
  type        = number
  default     = 0
}

variable "admin_secret_reader_role_arns" {
  description = <<-DESC
    Seal the bootstrap-admin secret (ADR-087): when non-empty, attach a resource policy to platform/keycloak/admin
    that DENIES secretsmanager:GetSecretValue to every principal whose role is NOT in this list — so even an
    AdministratorAccess principal can't read the crown-jewel credential. Pass the ROLE ARNs of the ONLY legitimate
    readers (each is expanded to its `:role/` and `:sts:…:assumed-role/…/*` forms): the deployer role (Terraform
    reads it on apply), the External Secrets Operator role (syncs it to the cluster), and a break-glass role.
    MISSING A READER temporarily breaks that reader (recoverable — the Deny is scoped to GetSecretValue, so
    PutResourcePolicy still works and an admin can fix it). Empty (default) = no policy = current behavior.
  DESC
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# Database (in-cluster CloudNativePG — dev; RDS is the prod toggle, deferred)
# ---------------------------------------------------------------------------

variable "database" {
  description = "Keycloak database. mode = in-cluster (CloudNativePG) | rds. For in-cluster, instances/storage_size size the CNPG Cluster."
  type = object({
    mode         = optional(string, "in-cluster")
    instances    = optional(number, 1)
    storage_size = optional(string, "8Gi")
    # Barman Cloud backups (#1119). enable_backups attaches the WAL archiver + creates the ObjectStore and a
    # daily ScheduledBackup (rolls the instance once). destination_path = bucket ROOT (barman appends the
    # server name = cluster) and must match the cluster's Pod-Identity role prefix scope.
    enable_backups   = optional(bool, false)
    destination_path = optional(string, "")
    retention        = optional(string, "30d")
  })
  default = {}
}

variable "backup_schedule" {
  description = "ScheduledBackup cron (CNPG 6-field, includes seconds). Top-level (not in the database object) so the cron renders in backticks — a cron inside a terraform-docs object-type block trips markdownlint MD037. Stagger across clusters to avoid simultaneous base backups."
  type        = string
  default     = "0 0 3 * * *"
}

variable "db_cluster_name" {
  description = "Name of the CloudNativePG Cluster (in-cluster mode). CNPG creates <name>-rw Service + <name>-app Secret."
  type        = string
  default     = "keycloak-db"
}

variable "rds_host" {
  description = "RDS Postgres hostname (rds mode)."
  type        = string
  default     = ""
}

variable "rds_secret_name" {
  description = "K8s Secret name holding RDS username/password (rds mode)."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Resources
# ---------------------------------------------------------------------------

variable "resources" {
  description = "Keycloak container resource requests/limits (JVM — size memory generously)."
  type = object({
    requests = optional(map(string), { cpu = "500m", memory = "1Gi" })
    limits   = optional(map(string), { cpu = "2", memory = "2Gi" })
  })
  default = {}
}

variable "tags" {
  description = "Tags (applied to Secrets Manager secrets; rendered as pod labels)"
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# Teardown: drain the CNPG database CR + PVC finalizers before the namespace delete
# ---------------------------------------------------------------------------

variable "finalizer_clear_script" {
  description = "Non-empty (and the in-cluster DB is used) enables a destroy-time provisioner that force-deletes the CNPG Cluster + its pods/PVCs so the namespace can finalize. Only checked for non-emptiness — the script itself is resolved at run time via the checkout's own `git rev-parse --show-toplevel`, not this value, so a worktree's different absolute path can't force a spurious null_resource replace. Kept as a path-shaped string for unit-wiring compatibility."
  type        = string
  default     = ""
}

variable "cluster_name" {
  description = "EKS cluster name — for the teardown finalizer-clear provisioner (aws eks update-kubeconfig)."
  type        = string
  default     = ""
}

variable "region" {
  description = "AWS region — for the teardown finalizer-clear provisioner."
  type        = string
  default     = ""
}

variable "deployer_role_arn" {
  description = "Deployer role ARN the teardown finalizer-clear provisioner assumes for cluster access."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Ingress — Keycloak self-owns its HTTPRoute on the shared Gateway (ADR-053/059)
# ---------------------------------------------------------------------------

variable "create_route" {
  description = "Create Keycloak's HTTPRoute (+ HTTP→HTTPS redirect) on the shared Gateway. Off by default; the unit enables it (needs the gateway dependency)."
  type        = bool
  default     = false
}

variable "gateway_name" {
  description = "Name of the shared Gateway to attach Keycloak's HTTPRoute to (parentRef)."
  type        = string
  default     = "platform-gateway"
}

variable "gateway_namespace" {
  description = "Namespace of the shared Gateway (parentRef)."
  type        = string
  default     = "default"
}
