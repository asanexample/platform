locals {
  create = var.create

  # Sanitize tags for K8s label compliance (RFC 1123): lowercase, valid chars, max 63 chars.
  k8s_labels = {
    for k, v in var.tags :
    replace(lower(k), "/[^a-z0-9_.-]/", "_") => replace(lower(v), "/[^a-z0-9_.-]/", "_")
    if length(replace(lower(k), "/[^a-z0-9_.-]/", "_")) <= 63 && length(replace(lower(v), "/[^a-z0-9_.-]/", "_")) <= 63
  }

  in_cluster_db = var.database.mode == "in-cluster"

  # Barman Cloud backups (#1119) for the in-cluster DB. backup_spec is merged into the Cluster spec so the
  # WAL-archiver plugin is absent (no reconcile churn) unless backups are on.
  db_backups_enabled = local.in_cluster_db && var.database.enable_backups
  backup_spec = local.db_backups_enabled ? {
    plugins = [{
      name          = "barman-cloud.cloudnative-pg.io"
      isWALArchiver = true
      parameters    = { barmanObjectName = "${var.db_cluster_name}-backup" }
    }]
  } : {}

  # Postgres connection. in-cluster: CloudNativePG creates the `<cluster>-rw` Service (read-write primary)
  # and the `<cluster>-app` Secret (owner user/password/dbname). rds: host + a Secrets-Manager-backed
  # Secret (the unit wires an ExternalSecret) supply the creds.
  db_host     = local.in_cluster_db ? "${var.db_cluster_name}-rw.${var.namespace}.svc.cluster.local" : var.rds_host
  db_secret   = local.in_cluster_db ? "${var.db_cluster_name}-app" : var.rds_secret_name
  db_user_key = local.in_cluster_db ? "username" : "username"
  db_pass_key = local.in_cluster_db ? "password" : "password"

  enable_oidc     = var.create && var.enable_oidc
  oidc_k8s_secret = "backstage-oidc"

  session_k8s_secret = "backstage-session"

  # Split-horizon host-alias for the OIDC issuer → the gateway's CURRENT ClusterIP (looked up below, not
  # hardcoded), plus any caller-supplied extras. Self-corrects on apply if the gateway Service is recreated.
  gateway_host_alias = var.create && var.oidc_gateway_alias_host != "" ? [{
    ip        = data.kubernetes_service_v1.gateway[0].spec[0].cluster_ip
    hostnames = [var.oidc_gateway_alias_host]
  }] : []
  host_aliases = concat(var.host_aliases, local.gateway_host_alias)

  # OIDC needs OIDC_CLIENT_SECRET (shared with Dex's staticClient, synced from Secrets Manager by the
  # ExternalSecret below) and a session-signing secret (AUTH_SESSION_SECRET — backstage-only, generated
  # here). The OAuth handshake stores state in a session cookie, so the oidc provider fails with
  # "authentication requires session support" unless auth.session.secret is set. Empty when OIDC disabled.
  oidc_env = local.enable_oidc ? [
    { name = "OIDC_CLIENT_SECRET", valueFrom = { secretKeyRef = { name = local.oidc_k8s_secret, key = var.oidc_secret_key } } },
    { name = "AUTH_SESSION_SECRET", valueFrom = { secretKeyRef = { name = local.session_k8s_secret, key = "session-secret" } } },
  ] : []

  # Injected as an extra app-config layer via the chart's appConfig (rendered to a ConfigMap + appended
  # to the --config chain). The ConfigMap holds only the ${ENV} placeholder; the value is in the env var.
  # $${...} escapes HCL interpolation so the literal ${AUTH_SESSION_SECRET} reaches Backstage.
  oidc_app_config = local.enable_oidc ? { auth = { session = { secret = "$${AUTH_SESSION_SECRET}" } } } : {}

  # GitHub App for catalog discovery (Phase 2.2). The read-only App's appId + private key (synced from
  # platform/backstage/github-app by the ExternalSecret below) feed integrations.github.apps in the image's
  # app-config.production.yaml. Empty env when disabled.
  github_enabled    = var.create && var.enable_github_discovery
  github_k8s_secret = "backstage-github-app"
  github_env = local.github_enabled ? [
    { name = "GITHUB_APP_ID", valueFrom = { secretKeyRef = { name = local.github_k8s_secret, key = "appId" } } },
    { name = "GITHUB_APP_PRIVATE_KEY", valueFrom = { secretKeyRef = { name = local.github_k8s_secret, key = "privateKey" } } },
  ] : []

  # The image's app-config.production.yaml now carries the complete integrations.github (clientId/clientSecret
  # placeholders) + the type-scoped catalog.rules (Phase 2.2 consolidation, asanexample/backstage#3), so the only
  # remaining chart appConfig layer is the OIDC session secret. The App's appId/privateKey are still injected
  # from the secret via github_env.

  # Scaffolder GitHub write App (BACK Phase 3, ADR-062 §5) — a SEPARATE App from the read-only discovery one,
  # installed on ONLY asanexample/platform with Contents + Pull Requests read/write (no admin, no
  # branch-protection bypass). appId + private key (synced from platform/backstage/scaffolder-github-app by
  # the ExternalSecret below) feed the second integrations.github.apps entry in the image's
  # app-config.production.yaml. The two Apps' installations must stay disjoint — see
  # docs/runbooks/backstage-scaffolder-github-app.md. Empty env when disabled.
  scaffolder_enabled    = var.create && var.enable_scaffolder
  scaffolder_k8s_secret = "backstage-scaffolder-github-app"
  scaffolder_env = local.scaffolder_enabled ? [
    { name = "SCAFFOLDER_GITHUB_APP_ID", valueFrom = { secretKeyRef = { name = local.scaffolder_k8s_secret, key = "appId" } } },
    { name = "SCAFFOLDER_GITHUB_APP_PRIVATE_KEY", valueFrom = { secretKeyRef = { name = local.scaffolder_k8s_secret, key = "privateKey" } } },
  ] : []

  enable_k8s = var.create && var.enable_kubernetes_plugin

  # Kubernetes plugin (Phase 2.4a): live cluster view. Injected as an appConfig layer (env-specific cluster
  # endpoints/CA/assume-role belong in the unit, not the image). authProvider=aws uses the pod's EKS Pod
  # Identity creds for THIS cluster; cross-account clusters set assumeRole (the read-only preprod Backstage role).
  kubernetes_app_config = local.enable_k8s ? {
    kubernetes = {
      serviceLocatorMethod = { type = "multiTenant" }
      clusterLocatorMethods = [{
        type = "config"
        clusters = [for c in var.kubernetes_clusters : merge({
          name         = c.name
          url          = c.url
          authProvider = "aws"
          caData       = c.ca_data
          region       = c.region
          # AmazonEKSViewPolicy doesn't grant the aggregated metrics.k8s.io API, so the optional pod-metrics
          # lookup 403s and shows a spurious "problem retrieving objects" warning. Skip it (workloads/health
          # still render). Grant metrics RBAC + flip this off later if CPU/memory usage is wanted.
          skipMetricsLookup = true
          },
          try(c.assume_role, null) != null && try(c.assume_role, "") != "" ? { assumeRole = c.assume_role } : {},
          # Crossplane self-service resource MRs (ADR-073/#574): surface live provisioning status (Ready/Syncing) of
          # an Environment's cloud resources on its catalog Kubernetes tab. The plugin only fetches *namespaced*
          # objects, so the Composition provisions these as the namespaced (aws.m.upbound.io) MR family in the env
          # namespace; the Environment entity's kubernetes-namespace + label-selector annotations (from
          # platform-projection) scope the query. Only the four primary resource kinds are surfaced (S3
          # sub-MRs/RolePolicy aren't developer-facing). Scoped PER-CLUSTER to the cross-account WORKLOAD clusters
          # (assume_role set) — the local platform/management cluster doesn't run the environment-api, so these CRDs
          # don't exist there and a global customResources would 403 on it (authz denies the unserved group before
          # the 404). New workload clusters inherit this automatically.
          try(c.assume_role, null) != null && try(c.assume_role, "") != "" ? { customResources = [
            { group = "s3.aws.m.upbound.io", apiVersion = "v1beta1", plural = "buckets" },
            { group = "sqs.aws.m.upbound.io", apiVersion = "v1beta1", plural = "queues" },
            { group = "sns.aws.m.upbound.io", apiVersion = "v1beta1", plural = "topics" },
            { group = "dynamodb.aws.m.upbound.io", apiVersion = "v1beta1", plural = "tables" },
          ] } : {},
        )]
      }]
    }
  } : {}

  # ArgoCD plugin (Phase 2.4b): the Roadie plugin reads our self-hosted ArgoCD read-only via a token. Instance
  # url(s) are env-specific (set in the unit); the token is supplied via the ARGOCD_AUTH_TOKEN env (synced from
  # Secrets Manager by the ExternalSecret below). $${...} escapes HCL so the literal ${ARGOCD_AUTH_TOKEN} reaches
  # Backstage's argocd config for the config loader to substitute.
  enable_argocd     = var.create && var.enable_argocd_plugin
  argocd_k8s_secret = "backstage-argocd-token"
  argocd_env = local.enable_argocd ? [
    { name = "ARGOCD_AUTH_TOKEN", valueFrom = { secretKeyRef = { name = local.argocd_k8s_secret, key = var.argocd_token_secret_key } } },
  ] : []

  # Durable-audit read (ADR-088 §3.6): the My Access view reads borrow HISTORY from the ADR-084 directory
  # Postgres. The connection (SM `uri`) is projected by the ExternalSecret below into AUDIT_DB_DSN; the backend
  # reads it env-side (a secret — never a flag). Empty audit_db_secret_id disables it (view degrades to
  # standing + live). The directory DB's CiliumNetworkPolicy must admit this namespace.
  enable_audit_db  = var.create && var.audit_db_secret_id != ""
  audit_k8s_secret = "backstage-audit-db"
  audit_env = local.enable_audit_db ? [
    { name = "AUDIT_DB_DSN", valueFrom = { secretKeyRef = { name = local.audit_k8s_secret, key = "dsn" } } },
  ] : []
  argocd_app_config = local.enable_argocd ? {
    argocd = {
      appLocatorMethods = [{
        type = "config"
        # `url` = the in-cluster API the backend calls; `frontendUrl` (when set) = the browser-facing UI for
        # "open in ArgoCD" links (the backend url is unreachable from the browser). token via env.
        instances = [for i in var.argocd_instances : merge(
          { name = i.name, url = i.url, token = "$${ARGOCD_AUTH_TOKEN}" },
          try(i.frontend_url, null) != null ? { frontendUrl = i.frontend_url } : {},
        )]
      }]
    }
  } : {}

  # platform-projection mode override (ADR-067 cutover): the image's app-config.production.yaml has no
  # platformProjection.mode (defaults to 'v2'); set projection_mode = "v3" at the unit to flip the catalog to
  # Product=System / Environment=custom-kind WITHOUT a new image (the L2c code is already in the image). Empty
  # = leave the image default.
  projection_app_config = var.projection_mode == "" ? {} : { platformProjection = { mode = var.projection_mode } }

  # TechDocs (#938, ADR-097): flip the image's scaffold-default techdocs config (builder=local, publisher=local)
  # to builder=external + publisher=awsS3, so Backstage SERVES the CI-published site from S3 — no runtime
  # generation, no mkdocs in the image. This --config override is appended last, so it wins over the base.
  enable_techdocs = var.create && var.enable_techdocs
  techdocs_app_config = local.enable_techdocs ? {
    techdocs = {
      builder = "external"
      publisher = {
        type = "awsS3"
        awsS3 = {
          bucketName = var.techdocs_bucket
          region     = var.region != "" ? var.region : "us-east-1"
        }
      }
    }
  } : {}

  extra_app_config = merge(local.oidc_app_config, local.kubernetes_app_config, local.argocd_app_config, local.projection_app_config, local.techdocs_app_config)

  backstage_values = {
    # We bring our own Postgres (CNPG or RDS) — never the chart's bundled bitnami Postgres.
    postgresql = { enabled = false }
    # Ingress is the Cilium Gateway (gateway-config HTTPRoute), not a K8s Ingress.
    ingress = { enabled = false }

    service = {
      type  = "ClusterIP"
      ports = { backend = 7007 }
    }

    serviceAccount = {
      create = true
      name   = "backstage"
      # No IRSA annotation, ever: AWS access (the 2.4a Kubernetes-plugin reader role) is granted via EKS
      # Pod Identity association (below), not an SA annotation — the platform standard (ADR-047).
    }

    # No ingress NetworkPolicy. Backstage now authenticates every request itself via direct Keycloak OIDC
    # (the `oidc` provider), so it is safe to be reached directly through the gateway — unlike the prior
    # `oauth2Proxy` header-trust provider, which required locking :7007 to the oauth2-proxy pod (the proxy
    # is retired). The portal is Tailscale-only externally; egress stays open (DB/GitHub/AWS/Keycloak).
    networkPolicy = {
      enabled = false
    }

    backstage = {
      image = {
        registry   = var.image_registry
        repository = var.image_repository
        tag        = var.image_tag
        pullPolicy = "IfNotPresent"
      }

      replicas       = var.replica_count
      containerPorts = { backend = 7007 }

      # Split-horizon: pin the OIDC issuer host to the gateway's ClusterIP (looked up dynamically below —
      # never hardcoded) so the backend reaches Keycloak via the gateway Envoy directly, not the flaky
      # internal-NLB hairpin. Plus any caller-supplied extra aliases.
      hostAliases = local.host_aliases

      # The chart overrides the image CMD, so re-supply the production config chain (both files are baked
      # into our image). Without the --config args the backend would load only the dev app-config.yaml.
      command = ["node", "packages/backend"]
      args    = ["--config", "app-config.yaml", "--config", "app-config.production.yaml"]

      extraEnvVars = concat([
        { name = "POSTGRES_HOST", value = local.db_host },
        { name = "POSTGRES_PORT", value = "5432" },
        { name = "POSTGRES_USER", valueFrom = { secretKeyRef = { name = local.db_secret, key = local.db_user_key } } },
        { name = "POSTGRES_PASSWORD", valueFrom = { secretKeyRef = { name = local.db_secret, key = local.db_pass_key } } },
      ], local.oidc_env, local.github_env, local.scaffolder_env, local.argocd_env, local.audit_env)

      # Extra app-config layer (chart renders it to a ConfigMap and appends --config): OIDC session
      # support (auth.session.secret) + the complete integrations.github (Phase 2.2). Empty {} when both off.
      appConfig = local.extra_app_config

      resources = var.resources

      # Hardening (the backstage namespace gets no tenant Kyverno mutate baseline — ADR-051 security).
      # readOnlyRootFilesystem is left false: the Backstage backend writes to a working dir (techdocs/
      # scaffolder); locking it down needs writable emptyDir mounts — a 2.1 hardening step.
      podSecurityContext = {
        runAsNonRoot   = true
        runAsUser      = 1000
        fsGroup        = 1000
        seccompProfile = { type = "RuntimeDefault" }
      }
      containerSecurityContext = {
        allowPrivilegeEscalation = false
        runAsNonRoot             = true
        capabilities             = { drop = ["ALL"] }
      }

      podLabels = local.k8s_labels
    }
  }
}

# ---------------------------------------------------------------------------
# Namespace (owns the DB Cluster + the helm release)
# ---------------------------------------------------------------------------

resource "kubernetes_namespace_v1" "backstage" {
  count = local.create ? 1 : 0

  metadata {
    name   = var.namespace
    labels = merge(local.k8s_labels, { "app.kubernetes.io/name" = "backstage" })
  }
}

# Teardown: drain the namespace's stateful contents before it is deleted. The namespace otherwise hangs in
# Terminating (the observed ~5m "context deadline exceeded") because a CNPG-left pod outlives the Cluster CR
# (terraform deletes the Cluster in ~1s, but its Succeeded pod stays stuck with no finalizer, the kubelet never
# confirming it) and pins its pvc-protection PVC. This runs FIRST on teardown (depends_on the namespace AND the
# db => reverse-order destroy puts it before both): it deletes the CNPG Cluster and force-evicts the stuck pods.
# NB: PVCs are deliberately NOT force-cleared here — doing so orphans the EBS volume (it bypasses the CSI
# delete). Evicting the pod releases pvc-protection, so the namespace-controller deletes the PVC through CSI,
# which cleans the EBS properly (CSI outlives this unit per the DAG). Best-effort + self-authenticating.
#
# The script path is resolved at RUN TIME via `git rev-parse --show-toplevel`, not baked into `triggers` as
# an absolute path — a worktree's checkout lives at a different absolute path than the main checkout, which
# would otherwise make a worktree apply look like a changed trigger and force a replace (firing this
# `when = destroy` provisioner outside of an actual teardown).
resource "null_resource" "namespace_drain" {
  count = local.create && var.finalizer_clear_script != "" ? 1 : 0

  triggers = {
    cluster   = var.cluster_name
    region    = var.region
    role_arn  = var.deployer_role_arn
    namespace = var.namespace
    refs      = "clusters.postgresql.cnpg.io pods"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "bash \"$(git rev-parse --show-toplevel)/scripts/k8s-finalizer-clear.sh\" --delete ${self.triggers.cluster} ${self.triggers.region} ${self.triggers.role_arn} ${self.triggers.namespace} ${self.triggers.refs}"
  }

  depends_on = [kubernetes_namespace_v1.backstage, kubernetes_manifest.db]

  # The `script` key is gone from `triggers` (see above) — pin its old value via ignore_changes so
  # existing state (which still has it) doesn't see that as a removed key and force a replace, which
  # would fire the destroy provisioner for real on a live cluster (verified: removing a `triggers` key
  # always forces replacement). A genuine change to cluster/region/role_arn/namespace/refs still
  # replaces normally.
  lifecycle {
    ignore_changes = [triggers["script"]]
  }
}

# ---------------------------------------------------------------------------
# In-cluster Postgres (CloudNativePG Cluster) — dev DB; RDS is the prod toggle
# ---------------------------------------------------------------------------

resource "kubernetes_manifest" "db" {
  count = local.create && local.in_cluster_db ? 1 : 0

  manifest = {
    apiVersion = "postgresql.cnpg.io/v1"
    kind       = "Cluster"
    metadata = {
      name      = var.db_cluster_name
      namespace = var.namespace
    }
    spec = merge({
      # imageName omitted → CNPG uses its default operand Postgres image for the operator version.
      instances = var.database.instances
      storage   = { size = var.database.storage_size }

      # Propagate the Karpenter do-not-disrupt annotation to the CNPG-managed instance Pods so Karpenter
      # won't voluntarily disrupt (consolidate/drift/expire) the node a Postgres primary/replica runs on.
      # inheritedMetadata is applied by CNPG to all Cluster-owned objects, the instance Pods included.
      inheritedMetadata = {
        annotations = { "karpenter.sh/do-not-disrupt" = "true" }
      }

      bootstrap             = { initdb = { database = "backstage", owner = "backstage" } }
      enableSuperuserAccess = false

      # Backstage creates a separate database per plugin (backstage_plugin_*) at startup, so its app role
      # needs CREATEDB. CNPG's initdb owner doesn't get it by default and we keep superuser access off, so
      # grant it declaratively via a managed role (reconciled onto the running cluster — no recreate, no
      # imperative `ALTER ROLE`). passwordSecret points at CNPG's generated app secret so the password is
      # left as-is.
      managed = {
        roles = [{
          name           = "backstage"
          ensure         = "present"
          login          = true
          createdb       = true
          passwordSecret = { name = "${var.db_cluster_name}-app" }
        }]
      }
    }, local.backup_spec)
  }

  depends_on = [kubernetes_namespace_v1.backstage]
}

# Barman Cloud backups (#1119): ObjectStore (S3 destination + retention; auth = inheritFromIAMRole via the
# cluster's Pod-Identity backup role) + a daily ScheduledBackup. encryption AES256 → barman sends the SSE
# header the org enforce-encryption SCP requires. destination_path is the bucket ROOT (barman appends the
# server name = cluster).
resource "kubernetes_manifest" "backup_object_store" {
  count = local.create && local.db_backups_enabled ? 1 : 0
  manifest = {
    apiVersion = "barmancloud.cnpg.io/v1"
    kind       = "ObjectStore"
    metadata   = { name = "${var.db_cluster_name}-backup", namespace = var.namespace }
    spec = {
      retentionPolicy = var.database.retention
      configuration = {
        destinationPath = var.database.destination_path
        s3Credentials   = { inheritFromIAMRole = true }
        wal             = { compression = "gzip", encryption = "AES256" }
        data            = { compression = "gzip", encryption = "AES256" }
      }
    }
  }
  depends_on = [kubernetes_namespace_v1.backstage]
}

resource "kubernetes_manifest" "scheduled_backup" {
  count = local.create && local.db_backups_enabled ? 1 : 0
  manifest = {
    apiVersion = "postgresql.cnpg.io/v1"
    kind       = "ScheduledBackup"
    metadata   = { name = "${var.db_cluster_name}-daily", namespace = var.namespace }
    spec = {
      schedule             = var.backup_schedule
      backupOwnerReference = "self"
      cluster              = { name = var.db_cluster_name }
      method               = "plugin"
      pluginConfiguration  = { name = "barman-cloud.cloudnative-pg.io" }
    }
  }
  depends_on = [kubernetes_manifest.db, kubernetes_manifest.backup_object_store]
}

# ---------------------------------------------------------------------------
# OIDC client secret (Phase 2.1) — synced from Secrets Manager by External Secrets.
# The secret itself is created by the dex module (platform/backstage/oidc); here we just
# project it into the backstage namespace as the K8s Secret backstage-oidc.
# ---------------------------------------------------------------------------

resource "kubernetes_manifest" "oidc_external_secret" {
  count = local.enable_oidc ? 1 : 0

  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = local.oidc_k8s_secret
      namespace = var.namespace
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef  = { name = var.secret_store_name, kind = "ClusterSecretStore" }
      target          = { name = local.oidc_k8s_secret, creationPolicy = "Owner" }
      data = [{
        secretKey = var.oidc_secret_key
        remoteRef = { key = var.oidc_secret_name, property = var.oidc_secret_key }
      }]
    }
  }

  depends_on = [kubernetes_namespace_v1.backstage]
}

# Durable-audit read (ADR-088 §3.6): project the ADR-084 directory Postgres connection (SM `uri`) into the
# backstage namespace as backstage-audit-db/dsn, which the backend reads as AUDIT_DB_DSN for the My Access
# view's borrow history.
resource "kubernetes_manifest" "audit_db_external_secret" {
  count = local.enable_audit_db ? 1 : 0

  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = local.audit_k8s_secret
      namespace = var.namespace
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef  = { name = var.secret_store_name, kind = "ClusterSecretStore" }
      target          = { name = local.audit_k8s_secret, creationPolicy = "Owner" }
      data = [{
        secretKey = "dsn"
        remoteRef = { key = var.audit_db_secret_id, property = "uri" }
      }]
    }
  }

  depends_on = [kubernetes_namespace_v1.backstage]
}

# ---------------------------------------------------------------------------
# GitHub App credential (Phase 2.2) — read-only App for catalog discovery.
# Created manually in Secrets Manager (the private key is GitHub-generated); see
# docs/runbooks/backstage-github-app.md. JSON keys: appId, privateKey.
# ---------------------------------------------------------------------------

resource "kubernetes_manifest" "github_app_external_secret" {
  count = local.github_enabled ? 1 : 0

  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = local.github_k8s_secret
      namespace = var.namespace
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef  = { name = var.secret_store_name, kind = "ClusterSecretStore" }
      target          = { name = local.github_k8s_secret, creationPolicy = "Owner" }
      data = [
        { secretKey = "appId", remoteRef = { key = var.github_app_secret_name, property = "appId" } },
        { secretKey = "privateKey", remoteRef = { key = var.github_app_secret_name, property = "privateKey" } },
      ]
    }
  }

  depends_on = [kubernetes_namespace_v1.backstage]
}

# ---------------------------------------------------------------------------
# Scaffolder GitHub write App credential (Phase 3, ADR-062 §5) — the separate write App the scaffolder uses
# to open PRs against asanexample/platform. Created manually in Secrets Manager (the private key is
# GitHub-generated); see docs/runbooks/backstage-scaffolder-github-app.md. JSON keys: appId, privateKey.
# ---------------------------------------------------------------------------

resource "kubernetes_manifest" "scaffolder_github_app_external_secret" {
  count = local.scaffolder_enabled ? 1 : 0

  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = local.scaffolder_k8s_secret
      namespace = var.namespace
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef  = { name = var.secret_store_name, kind = "ClusterSecretStore" }
      target          = { name = local.scaffolder_k8s_secret, creationPolicy = "Owner" }
      data = [
        { secretKey = "appId", remoteRef = { key = var.scaffolder_github_app_secret_name, property = "appId" } },
        { secretKey = "privateKey", remoteRef = { key = var.scaffolder_github_app_secret_name, property = "privateKey" } },
      ]
    }
  }

  depends_on = [kubernetes_namespace_v1.backstage]
}

# ---------------------------------------------------------------------------
# ArgoCD read-only token (Phase 2.4b) — synced from Secrets Manager (platform/argocd/backstage-token, minted
# out-of-band against the read-only `backstage` ArgoCD account; see docs/runbooks/backstage-argocd.md) into the
# backstage namespace as backstage-argocd-token, then injected as ARGOCD_AUTH_TOKEN.
# ---------------------------------------------------------------------------

resource "kubernetes_manifest" "argocd_token_external_secret" {
  count = local.enable_argocd ? 1 : 0

  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = local.argocd_k8s_secret
      namespace = var.namespace
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef  = { name = var.secret_store_name, kind = "ClusterSecretStore" }
      target          = { name = local.argocd_k8s_secret, creationPolicy = "Owner" }
      data = [{
        secretKey = var.argocd_token_secret_key
        remoteRef = { key = var.argocd_token_secret_name, property = var.argocd_token_secret_key }
      }]
    }
  }

  depends_on = [kubernetes_namespace_v1.backstage]
}

# ---------------------------------------------------------------------------
# Session-signing secret (Phase 2.1) — backstage-only, generated here (not shared, so no
# Secrets Manager round-trip needed). Backed AUTH_SESSION_SECRET; stable across applies.
# ---------------------------------------------------------------------------

resource "random_password" "session" {
  count   = local.enable_oidc ? 1 : 0
  length  = 64
  special = false
}

resource "kubernetes_secret_v1" "session" {
  count = local.enable_oidc ? 1 : 0

  metadata {
    name      = local.session_k8s_secret
    namespace = var.namespace
  }
  data = { "session-secret" = random_password.session[0].result }

  depends_on = [kubernetes_namespace_v1.backstage]
}

# ---------------------------------------------------------------------------
# Kubernetes plugin AWS access (Phase 2.4a) — read-only, EKS Pod Identity.
# The `backstage` ServiceAccount is bound (Pod Identity, no SA annotation — ADR-047) to a reader role with
# cluster-View access on THIS (platform) cluster, plus permission to assume the cross-account read-only
# Backstage role(s) on the workload cluster(s). All read-only: AmazonEKSViewPolicy excludes Secrets.
# The role uses a name_prefix so the workload-account Backstage role can trust it via an ArnLike pattern.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "k8s_reader_trust" {
  count = local.enable_k8s ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "k8s_reader" {
  count = local.enable_k8s ? 1 : 0

  name_prefix        = "${var.cluster_name}-backstage-"
  assume_role_policy = data.aws_iam_policy_document.k8s_reader_trust[0].json
  tags               = var.tags
}

# Allow assuming the cross-account read-only Backstage role(s) on the workload cluster(s).
resource "aws_iam_role_policy" "k8s_reader_remote" {
  count = local.enable_k8s && length(var.remote_cluster_role_arns) > 0 ? 1 : 0

  name = "remote-cluster-read"
  role = aws_iam_role.k8s_reader[0].id

  # sts:TagSession as well as sts:AssumeRole — the Backstage k8s AWS auth assumes the cross-account role
  # with a tagged session (the target role's trust must also allow TagSession).
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = ["sts:AssumeRole", "sts:TagSession"], Resource = var.remote_cluster_role_arns }]
  })
}

resource "aws_eks_pod_identity_association" "k8s_reader" {
  count = local.enable_k8s ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = "backstage"
  role_arn        = aws_iam_role.k8s_reader[0].arn
  tags            = var.tags
}

# TechDocs S3 read (#938, ADR-097): the Backstage pod (via its k8s_reader Pod-Identity role) reads the
# CI-published site from the techdocs bucket. Same-account, so an identity policy suffices (no bucket
# policy). Attached to k8s_reader because that is the Backstage SA's Pod-Identity role — hence enable_techdocs
# requires enable_kubernetes_plugin.
resource "aws_iam_role_policy" "techdocs_read" {
  count = local.enable_techdocs && local.enable_k8s ? 1 : 0

  name = "techdocs-read"
  role = aws_iam_role.k8s_reader[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["s3:GetObject", "s3:ListBucket"]
      Resource = [
        "arn:aws:s3:::${var.techdocs_bucket}",
        "arn:aws:s3:::${var.techdocs_bucket}/*",
      ]
    }]
  })
}

# Read-only access on the platform cluster itself (the workload clusters grant their own access entries).
# The `backstage-activators` group is the ONE write capability (ADR-088): the activation-operator chart binds
# it to create-only on Activations, so the Activate Power backend (this pod) can create a borrow — and
# nothing else. The AmazonEKSViewPolicy below stays read-only (no Secrets); the group adds only that grant.
resource "aws_eks_access_entry" "k8s_reader" {
  count = local.enable_k8s ? 1 : 0

  cluster_name      = var.cluster_name
  principal_arn     = aws_iam_role.k8s_reader[0].arn
  kubernetes_groups = ["backstage-activators"]
  type              = "STANDARD"
}

resource "aws_eks_access_policy_association" "k8s_reader" {
  count = local.enable_k8s ? 1 : 0

  cluster_name  = var.cluster_name
  principal_arn = aws_iam_role.k8s_reader[0].arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"

  access_scope { type = "cluster" }

  depends_on = [aws_eks_access_entry.k8s_reader]
}

# ---------------------------------------------------------------------------
# Backstage (official chart, our image)
# ---------------------------------------------------------------------------

resource "helm_release" "backstage" {
  count            = local.create ? 1 : 0
  name             = var.helm_release_name
  repository       = var.helm_repository
  chart            = var.helm_chart
  version          = var.helm_chart_version
  namespace        = var.namespace
  create_namespace = false # the namespace resource above owns it
  timeout          = var.helm_timeout
  wait             = var.helm_wait
  atomic           = false # don't auto-rollback: the DB Cluster provisions async; verify health out of band
  cleanup_on_fail  = false
  replace          = true

  values = [yamlencode(local.backstage_values)]

  depends_on = [
    kubernetes_namespace_v1.backstage,
    kubernetes_manifest.db,
    kubernetes_manifest.oidc_external_secret,
    kubernetes_secret_v1.session,
    kubernetes_manifest.github_app_external_secret,
    kubernetes_manifest.scaffolder_github_app_external_secret,
    kubernetes_manifest.argocd_token_external_secret,
    # Pod Identity must exist before the pod starts, or it gets no AWS creds until a restart.
    aws_eks_pod_identity_association.k8s_reader,
  ]
}

# ---------------------------------------------------------------------------
# Gateway ClusterIP lookup (split-horizon OIDC host-alias — see local.gateway_host_alias).
# Reads the CURRENT ClusterIP of the shared Cilium gateway Service so the OIDC issuer host-alias is never a
# hardcoded snapshot; it re-resolves on every apply (self-heals if the Service is recreated).
# ---------------------------------------------------------------------------
data "kubernetes_service_v1" "gateway" {
  count = var.create && var.oidc_gateway_alias_host != "" ? 1 : 0

  metadata {
    name      = var.gateway_service_name
    namespace = var.gateway_service_namespace
  }
}
