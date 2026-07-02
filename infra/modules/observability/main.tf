locals {
  create     = var.create
  create_sns = local.create && var.alerts_topic_arn != "" # SNS-publish role for Alertmanager (Pod Identity)
  # P5a — Grafana CloudWatch datasource (zero-storage, query-time AWS-resource metrics). Grafana's SA gets
  # CloudWatch read via Pod Identity (ADR-047 — no IRSA annotation needed); the datasource uses the pod creds.
  cloudwatch_enabled = local.create && var.cloudwatch_enabled

  # Sanitize tags for K8s label compliance (RFC-1123), mirroring the policy module.
  k8s_labels = {
    for k, v in var.tags :
    replace(lower(k), "/[^a-z0-9_.-]/", "_") => replace(lower(v), "/[^a-z0-9_.-]/", "_")
    if length(replace(lower(k), "/[^a-z0-9_.-]/", "_")) <= 63 && length(replace(lower(v), "/[^a-z0-9_.-]/", "_")) <= 63
  }

  # Deterministic names (release pinned so these are stable).
  grafana_service       = "${var.helm_release_name}-grafana"
  alertmanager_sa       = "${var.helm_release_name}-alertmanager"
  grafana_admin_secret  = "grafana-admin"
  grafana_admin_sm_name = "${var.secret_path_prefix}/observability/grafana-admin"
  prometheus_storage_spec = var.use_persistent_storage ? {
    volumeClaimTemplate = {
      spec = {
        storageClassName = var.storage_class
        accessModes      = ["ReadWriteOnce"]
        resources        = { requests = { storage = "20Gi" } }
      }
    }
  } : null

  alertmanager_storage_spec = var.use_persistent_storage ? {
    volumeClaimTemplate = {
      spec = {
        storageClassName = var.storage_class
        accessModes      = ["ReadWriteOnce"]
        resources        = { requests = { storage = "5Gi" } }
      }
    }
  } : null

  # Grafana's SQLite state (service accounts, API tokens, org/user settings, UI-created alert rules) lives on
  # the pod filesystem unless persistence is wired (#1070). useStatefulSet turns the chart's persistence PVC
  # into a per-replica volumeClaimTemplate — required once replicas > 1, since a plain Deployment would mount
  # one ReadWriteOnce PVC into every replica pod.
  grafana_persistence = {
    enabled          = var.use_persistent_storage
    type             = "pvc"
    storageClassName = var.storage_class
    accessModes      = ["ReadWriteOnce"]
    size             = "5Gi"
  }

  # Prometheus -> Mimir remote_write (durable multi-tenant store, #102 P2). Empty url = off (P1 behaviour).
  #
  # Two modes:
  #   • Direct (default): one static X-Scope-OrgID header stamps ALL hub metrics into `mimir_tenant_id`.
  #   • Per-team (P13, #590): when cortex_tenant_write_url is set, write to cortex-tenant instead — a forced
  #     2-step relabel derives a `tenant` label from the namespace (unconditional `platform` first, so a pod
  #     can't spoof it, then override to the team for env namespaces), and cortex-tenant sets X-Scope-OrgID
  #     per-series from that label. No request header (cortex-tenant owns it). On the hub, which has no env
  #     namespaces, every series resolves to `platform` — behaviourally identical, but it proves the path.
  # Both branches must yield the same object type (Terraform ?: rule), so `headers` and
  # `writeRelabelConfigs` are always present — empty (no-op) in the mode that doesn't use them.
  _per_team_write = var.cortex_tenant_write_url != ""
  prometheus_remote_write = var.mimir_remote_write_url == "" ? [] : [{
    url     = local._per_team_write ? var.cortex_tenant_write_url : var.mimir_remote_write_url
    headers = local._per_team_write ? {} : { "X-Scope-OrgID" = var.mimir_tenant_id }
    writeRelabelConfigs = local._per_team_write ? [
      { sourceLabels = ["namespace"], regex = ".*", targetLabel = "tenant", replacement = "platform" },
      { sourceLabels = ["namespace"], regex = "([a-z0-9]+)-[a-z0-9-]+-(dev|test|uat|staging|prod)", targetLabel = "tenant", replacement = "$1" },
    ] : []
  }]

  # Slack/PagerDuty receivers wired when their secret names are provided (synced via External Secrets).
  slack_enabled = var.slack_webhook_secret_name != ""
  # ADR-082: fan a curated alert subset to the triage agent's in-cluster webhook (empty url = off).
  triage_enabled    = var.triage_webhook_url != ""
  pagerduty_enabled = var.pagerduty_routing_key_secret_name != ""
  # Dead-man's switch (external heartbeat): route the always-firing Watchdog to an EXTERNAL Healthchecks.io
  # check; if the pings stop (Prometheus/Alertmanager dead) Healthchecks pages — the one failure the in-cluster
  # pipeline can't alert on itself.
  deadman_enabled = var.healthchecks_ping_url_secret_name != ""

  # Grafana SSO via Keycloak OIDC (#592). On when an issuer is provided; the client secret syncs via ESO and
  # is injected as the GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET env (so it never enters grafana.ini / state).
  grafana_oidc_enabled  = local.create && var.grafana_oidc_issuer != "" && var.grafana_oidc_secret_manager_key != ""
  grafana_oidc_secret   = "grafana-oidc"
  grafana_oidc_alias_on = local.grafana_oidc_enabled && var.oidc_gateway_alias_host != ""

  # Split-horizon host-alias: pin the issuer host to the gateway Envoy ClusterIP (looked up below, never
  # hardcoded) so Grafana's backend OIDC calls bypass the internal-NLB hairpin. Mirrors Backstage.
  grafana_host_aliases = local.grafana_oidc_alias_on ? [{
    ip        = data.kubernetes_service_v1.gateway[0].spec[0].cluster_ip
    hostnames = [var.oidc_gateway_alias_host]
  }] : []

  grafana_oauth_ini = local.grafana_oidc_enabled ? {
    "auth.generic_oauth" = {
      enabled = true
      name    = "Keycloak"
      # client_secret comes from the GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET env (envValueFrom below).
      client_id           = var.grafana_oidc_client_id
      scopes              = "openid profile email groups"
      auth_url            = "${var.grafana_oidc_issuer}/protocol/openid-connect/auth"
      token_url           = "${var.grafana_oidc_issuer}/protocol/openid-connect/token"
      api_url             = "${var.grafana_oidc_issuer}/protocol/openid-connect/userinfo"
      role_attribute_path = var.grafana_oidc_role_attribute_path
      allow_sign_up       = true
      use_pkce            = true
    }
  } : {}

  # SNS receiver config (severity is in the subject) — shared across receivers.
  sns_config = {
    topic_arn     = var.alerts_topic_arn
    sigv4         = { region = var.aws_region }
    subject       = "[{{ .CommonLabels.severity }}] {{ .CommonLabels.alertname }}"
    message       = "{{ range .Alerts }}{{ .Annotations.description }}{{ \"\\n\" }}{{ end }}"
    send_resolved = true
  }

  # Slack receiver config. api_url_file reads the webhook from the mounted ES-synced secret, so the URL
  # never enters Terraform state or the helm values. The incoming webhook is bound to its own channel.
  slack_config = {
    api_url_file  = "/etc/alertmanager/secrets/alertmanager-slack-webhook/url"
    channel       = var.slack_channel
    send_resolved = true
  }

  # PagerDuty receiver config (Events API v2). routing_key_file reads the integration key from the mounted
  # ES-synced secret (URL/key never enters state or helm values). Only critical alerts page.
  pagerduty_config = {
    routing_key_file = "/etc/alertmanager/secrets/alertmanager-pagerduty/routingKey"
    severity         = "critical"
    description      = "{{ .CommonLabels.alertname }} ({{ .CommonLabels.namespace }})"
    send_resolved    = true
  }

  # Dead-man's switch receiver: on every Watchdog notification, POST to the external Healthchecks.io ping URL.
  # url_file reads the ping URL from the ES-synced secret so it never enters state/helm values (like Slack's
  # api_url_file). Healthchecks pages EXTERNALLY if the pings stop — detecting a dead in-cluster pipeline.
  deadman_config = {
    url_file      = "/etc/alertmanager/secrets/alertmanager-healthchecks/pingUrl"
    send_resolved = false
  }

  # Alertmanager routing (P4): critical → SNS + Slack, warning → Slack (SNS fallback when Slack is off);
  # info/others → dashboard-only (null); Watchdog → the external dead-man's switch (Healthchecks) when
  # configured, else null. A critical
  # inhibits a matching warning (same namespace+alertname) so one incident doesn't double-notify. Each
  # receiver carries only the channels actually wired (SNS needs the topic+IRSA; Slack needs the secret);
  # with neither, the receivers are no-ops (== null).
  alertmanager_config = {
    global = { resolve_timeout = "5m" }
    route = {
      group_by        = ["namespace", "alertname"]
      group_wait      = "30s"
      group_interval  = "5m"
      repeat_interval = "4h"
      receiver        = "null"
      # Watchdog → null (and does NOT reach triage, since it has no `continue`). The triage route (ADR-082) fans a
      # curated subset (critical) to the agent's webhook ADDITIVELY — `continue = true` so the same alert still
      # flows on to the critical receiver (SNS/Slack/PagerDuty). The agent's own storm controls (ADR-080 D9) bound it.
      routes = concat(
        # Watchdog → the external dead-man's switch when configured (pinged every ~5m; Healthchecks pages if
        # they stop), else → null. Never reaches triage/critical/warning (no `continue`).
        [local.deadman_enabled
          ? { receiver = "deadmanswitch", matchers = ["alertname = \"Watchdog\""], group_wait = "0s", group_interval = "1m", repeat_interval = "5m" }
        : { receiver = "null", matchers = ["alertname = \"Watchdog\""], group_wait = "0s", group_interval = "1m", repeat_interval = "5m" }],
        local.triage_enabled ? [{ receiver = "triage", matchers = ["severity = \"critical\""], continue = true }] : [],
        [
          { receiver = "critical", matchers = ["severity = \"critical\""], continue = false },
          { receiver = "warning", matchers = ["severity = \"warning\""], continue = false },
        ],
      )
    }
    inhibit_rules = [{
      source_matchers = ["severity = \"critical\""]
      target_matchers = ["severity = \"warning\""]
      equal           = ["namespace", "alertname"]
    }]
    # critical → SNS (if IRSA) + Slack (if enabled); warning → Slack (if enabled), else SNS fallback.
    # Config keys are always present as lists (empty = that channel off) so critical/warning share one
    # object type; concat keeps the differently-shaped "null" receiver separate.
    receivers = concat(
      [{ name = "null" }],
      # The triage agent's webhook (ADR-082) — a curated subset is fanned here additively (the route above).
      local.triage_enabled ? [{
        name            = "triage"
        webhook_configs = [{ url = var.triage_webhook_url, send_resolved = false }]
      }] : [],
      local.deadman_enabled ? [{
        name            = "deadmanswitch"
        webhook_configs = [local.deadman_config]
      }] : [],
      [
        {
          name              = "critical"
          sns_configs       = local.create_sns ? [local.sns_config] : []
          slack_configs     = local.slack_enabled ? [local.slack_config] : []
          pagerduty_configs = local.pagerduty_enabled ? [local.pagerduty_config] : []
        },
        {
          name              = "warning"
          sns_configs       = (!local.slack_enabled && local.create_sns) ? [local.sns_config] : []
          slack_configs     = local.slack_enabled ? [local.slack_config] : []
          pagerduty_configs = [] # warnings notify Slack/SNS, they don't page
        },
      ],
    )
  }

  helm_values = {
    # --- EKS accuracy: managed control plane is unscrapeable; Cilium replaces kube-proxy. ---
    # Disable the scrape jobs AND their alert rule groups so we don't ship empty dashboards
    # or perpetually-firing "target down" alerts.
    kubeScheduler         = { enabled = false }
    kubeControllerManager = { enabled = false }
    kubeEtcd              = { enabled = false }
    kubeProxy             = { enabled = false }

    defaultRules = {
      create = true
      rules = {
        etcd                  = false
        kubeScheduler         = false
        kubeControllerManager = false
        kubeProxy             = false
      }
    }

    # Curated platform-specific alert rules (P4 Tier 2) — one group per component, PromQL grounded in
    # metrics verified present in Prometheus. Severity labels route via the Alertmanager tree; each
    # alert carries a runbook_url. Cilium/ESO/stores join once their metrics are scraped (follow-up).
    additionalPrometheusRulesMap = {
      "platform-curated" = yamldecode(file("${path.module}/alerts/curated.yaml"))
    }

    # --- Prometheus ---
    prometheus = {
      prometheusSpec = {
        replicas  = var.high_availability ? 2 : 1
        retention = var.prometheus_retention
        # Karpenter must not voluntarily disrupt (consolidate/drift/expire) the node a Prometheus pod runs on
        # (PVC-backed TSDB). The prometheus-operator propagates prometheusSpec.podMetadata.annotations onto
        # the StatefulSet pods it generates from this Prometheus CR.
        podMetadata = { annotations = { "karpenter.sh/do-not-disrupt" = "true" } }
        # Tag every series with the source cluster (the multi-cluster dimension). Clean name (e.g. `platform`)
        # matching the tenant/env, not the raw EKS cluster ID; falls back to cluster_name if unset.
        externalLabels = { cluster = var.cluster_label != "" ? var.cluster_label : var.cluster_name }
        # Ship to Mimir for durable, long-range storage (empty when no Mimir url is set).
        remoteWrite = local.prometheus_remote_write
        # Pick up ServiceMonitors / PodMonitors / Rules cluster-wide, not just chart-labelled ones
        # (so the per-component ServiceMonitors below — and future ones — are scraped).
        serviceMonitorSelectorNilUsesHelmValues = false
        podMonitorSelectorNilUsesHelmValues     = false
        ruleSelectorNilUsesHelmValues           = false
        probeSelectorNilUsesHelmValues          = false
        resources = {
          requests = { cpu = "200m", memory = "1Gi" }
          limits   = { memory = "2Gi" }
        }
        storageSpec     = local.prometheus_storage_spec
        podAntiAffinity = var.high_availability ? "hard" : "soft"
      }
      # Per-component ServiceMonitors for the tier-2 dashboards (sources that already expose metrics).
      # ArgoCD / Cilium-agent / External-Secrets need a metrics flag in their own unit first — added as
      # those units enable metrics (follow-up).
      additionalServiceMonitors = [
        {
          name              = "kyverno"
          namespaceSelector = { matchNames = ["kyverno"] }
          selector          = { matchLabels = { "app.kubernetes.io/part-of" = "kyverno" } }
          endpoints         = [{ port = "metrics-port", interval = "30s" }]
        },
        {
          name              = "cert-manager"
          namespaceSelector = { matchNames = ["cert-manager"] }
          selector          = { matchLabels = { "app.kubernetes.io/name" = "cert-manager" } }
          endpoints         = [{ port = "tcp-prometheus-servicemonitor", interval = "30s" }]
        },
        {
          # ESO exposes a metrics Service (metrics_enabled in the external-secrets unit), but the chart's
          # own ServiceMonitor is capability-gated and didn't render via the helm provider — define it
          # here instead (the "metrics" port; the webhook service lacks it and is skipped).
          name              = "external-secrets"
          namespaceSelector = { matchNames = ["external-secrets"] }
          selector          = { matchLabels = { "app.kubernetes.io/name" = "external-secrets" } }
          endpoints         = [{ port = "metrics", interval = "30s" }]
        },
        {
          # Hubble metrics Service (Cilium flow observability). Agent/operator metrics have no Service —
          # they're scraped via additionalPodMonitors below.
          name              = "hubble"
          namespaceSelector = { matchNames = ["kube-system"] }
          selector          = { matchLabels = { "k8s-app" = "hubble" } }
          endpoints         = [{ port = "hubble-metrics", interval = "30s" }]
        },
      ]

      # Cilium agent + operator expose Prometheus metrics on the pods (prometheus.enabled is on), but the
      # cilium chart's ServiceMonitors are intentionally off (Cilium installs before the Prometheus-operator
      # CRDs in the DAG). Scrape the pods directly here, where the CRDs exist — no CNI change needed.
      additionalPodMonitors = [
        {
          name                = "cilium-agent"
          namespaceSelector   = { matchNames = ["kube-system"] }
          selector            = { matchLabels = { "k8s-app" = "cilium" } }
          podMetricsEndpoints = [{ port = "prometheus", interval = "30s" }]
        },
        {
          name                = "cilium-operator"
          namespaceSelector   = { matchNames = ["kube-system"] }
          selector            = { matchLabels = { "io.cilium/app" = "operator" } }
          podMetricsEndpoints = [{ port = "prometheus", interval = "30s" }]
        },
      ]
    }

    # --- Alertmanager ---
    alertmanager = {
      alertmanagerSpec = {
        replicas        = var.high_availability ? 3 : 1
        podAntiAffinity = var.high_availability ? "hard" : "soft"
        # Karpenter must not voluntarily disrupt (consolidate/drift/expire) the node an Alertmanager pod runs
        # on (PVC-backed silence/notification state). The prometheus-operator propagates
        # alertmanagerSpec.podMetadata.annotations onto the StatefulSet pods it generates from the Alertmanager CR.
        podMetadata = { annotations = { "karpenter.sh/do-not-disrupt" = "true" } }
        resources = {
          requests = { cpu = "50m", memory = "128Mi" }
          limits   = { memory = "256Mi" }
        }
        storage = local.alertmanager_storage_spec
        # Mount the ES-synced Slack webhook at /etc/alertmanager/secrets/<name>/url (referenced by the
        # Slack receiver's api_url_file). The K8s secret is created by the ExternalSecret below.
        secrets = concat(
          local.slack_enabled ? ["alertmanager-slack-webhook"] : [],
          local.pagerduty_enabled ? ["alertmanager-pagerduty"] : [],
          local.deadman_enabled ? ["alertmanager-healthchecks"] : [],
        )
      }
      serviceAccount = {
        # Pod Identity (ADR-047) — no IRSA annotation; the association binds this SA -> the SNS-publish role.
        annotations = {}
      }
      config = local.alertmanager_config
    }

    # --- Grafana (hardened; admin via the TF-managed secret; SSO is a fast-follow) ---
    grafana = {
      replicas       = var.high_availability ? 2 : 1
      useStatefulSet = var.use_persistent_storage
      persistence    = local.grafana_persistence
      admin = {
        existingSecret = local.grafana_admin_secret
        userKey        = "admin-user"
        passwordKey    = "admin-password"
      }
      defaultDashboardsEnabled  = true # tier-1 bundled dashboards
      defaultDashboardsTimezone = "utc"
      sidecar = {
        dashboards = { enabled = true, label = "grafana_dashboard", searchNamespace = var.namespace, folderAnnotation = "grafana_folder", provider = { foldersFromFilesStructure = true } }
        # When Mimir is wired (remote_write set), stop marking the bundled Prometheus datasource default so
        # the Mimir datasource (durable, full-range) becomes Grafana's primary. Prometheus stays selectable.
        datasources = { enabled = true, defaultDatasourceEnabled = var.mimir_remote_write_url == "" }
      }
      service = { port = 80 }
      # P5a — CloudWatch datasource (query-time, no storage). authType "default" picks up the Grafana SA's
      # Pod-Identity creds (CloudWatch read). Covers NLB/S3/TGW/NAT/Route53/EKS metrics with no exporter.
      additionalDataSources = local.cloudwatch_enabled ? [{
        name = "CloudWatch"
        type = "cloudwatch"
        uid  = "cloudwatch"
        jsonData = {
          authType      = "default"
          defaultRegion = var.aws_region
        }
      }] : []
      # grafana.ini: base hardening + (when SSO is on) the Keycloak generic_oauth block merged in.
      "grafana.ini" = merge({
        server           = { root_url = "https://${var.grafana_hostname}", enforce_domain = false }
        "auth.anonymous" = { enabled = false }
        users            = { viewers_can_edit = false, allow_sign_up = false, allow_org_create = false, default_theme = "dark" }
        security         = { cookie_secure = true, cookie_samesite = "strict", content_security_policy = true, disable_gravatar = true }
        plugins          = { allow_loading_unsigned_plugins = "" }
        analytics        = { reporting_enabled = false, check_for_updates = false }
      }, local.grafana_oauth_ini)

      # Inject the OIDC client secret from the ESO-synced K8s secret (never in grafana.ini / state).
      envValueFrom = local.grafana_oidc_enabled ? {
        GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET = {
          secretKeyRef = { name = local.grafana_oidc_secret, key = "client-secret" }
        }
      } : {}

      # Pin the issuer host to the gateway Envoy ClusterIP so backend OIDC calls dodge the internal-NLB hairpin.
      hostAliases = local.grafana_host_aliases

      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { memory = "512Mi" }
      }
    }

    # node-exporter needs host access — the ns is created (below) with PSA `privileged` for it.
    "kube-state-metrics" = {}
    nodeExporter         = { enabled = true }
  }
}

# ---------------------------------------------------------------------------
# Namespace (PSA `privileged` for node-exporter; created here, NOT by the chart,
# so the label is set — and intentionally NO tenant label).
# ---------------------------------------------------------------------------
resource "kubernetes_namespace_v1" "this" {
  count = local.create ? 1 : 0

  metadata {
    name = var.namespace
    labels = merge(local.k8s_labels, {
      "pod-security.kubernetes.io/enforce" = "privileged"
      "app.kubernetes.io/managed-by"       = "terraform"
    })
  }
}

# Teardown: drain the namespace's stateful workloads before it is deleted. The namespace otherwise hangs in
# Terminating (the observed ~5m "context deadline exceeded") on Succeeded prometheus/mimir/alertmanager pods
# (no finalizer, kubelet never confirmed) pinning their pvc-protection PVCs. This runs FIRST on teardown
# (depends_on the namespace AND the helm release => reverse-order destroy puts it before both). It deletes the
# StatefulSets/Deployments/DaemonSets first so the helm-managed pods can't recreate, then force-evicts the
# leftover pods. NB: PVCs are deliberately NOT force-cleared — that orphans the EBS volume (bypasses the CSI
# delete). Evicting the pods releases pvc-protection, so the namespace-controller deletes the PVCs through CSI,
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
    region    = var.aws_region
    role_arn  = var.deployer_role_arn
    namespace = var.namespace
    refs      = "statefulsets.apps deployments.apps daemonsets.apps pods"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "bash \"$(git rev-parse --show-toplevel)/scripts/k8s-finalizer-clear.sh\" --delete ${self.triggers.cluster} ${self.triggers.region} ${self.triggers.role_arn} ${self.triggers.namespace} ${self.triggers.refs}"
  }

  depends_on = [kubernetes_namespace_v1.this, helm_release.kube_prometheus_stack]

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
# Network policies — default-deny ingress; allow intra-namespace; Grafana reachable
# (gateway path). Egress left open (Prometheus scrapes cluster-wide). Full store-endpoint
# isolation lands with the multi-tenant stores in P2.
# ---------------------------------------------------------------------------
resource "kubernetes_network_policy_v1" "default_deny_ingress" {
  count = local.create ? 1 : 0

  metadata {
    name      = "default-deny-ingress"
    namespace = kubernetes_namespace_v1.this[0].metadata[0].name
  }
  spec {
    pod_selector {}
    policy_types = ["Ingress"]
  }
}

resource "kubernetes_network_policy_v1" "allow_intra_namespace" {
  count = local.create ? 1 : 0

  metadata {
    name      = "allow-intra-namespace"
    namespace = kubernetes_namespace_v1.this[0].metadata[0].name
  }
  spec {
    pod_selector {}
    policy_types = ["Ingress"]
    ingress {
      from {
        pod_selector {}
      }
    }
  }
}

# Platform agents (ADR-082, runtime=platform-agent namespaces) READ the obs stores in-cluster: the triage
# agent queries loki-gateway/mimir-gateway and exports traces to otel-collector. The ns default-denies ingress,
# so explicitly admit the agent namespaces (identity-based namespaceSelector — works on Cilium, unlike a CIDR
# ipBlock). Read-only data; the agent's obs-read RBAC already scopes WHAT it can read. No-op where no agents run.
resource "kubernetes_network_policy_v1" "allow_platform_agent_read" {
  count = local.create ? 1 : 0

  metadata {
    name      = "allow-platform-agent-read"
    namespace = kubernetes_namespace_v1.this[0].metadata[0].name
  }
  spec {
    pod_selector {}
    policy_types = ["Ingress"]
    ingress {
      from {
        namespace_selector {
          match_labels = {
            "platform.refplat.org/runtime" = "platform-agent"
          }
        }
      }
    }
  }
}

# OTLP ingress to the collector for platform control-plane add-ons that EMIT telemetry (e.g. the ADR-088
# activation operator). default-deny-ingress otherwise blocks them; this is a reusable, scoped grant — only
# the collector pod, only the OTLP ports (4317 gRPC / 4318 HTTP), only from namespaces a platform operator
# explicitly labels `platform.refplat.org/otel-export = "true"`.
resource "kubernetes_network_policy_v1" "allow_otlp_from_platform_telemetry" {
  count = local.create ? 1 : 0

  metadata {
    name      = "allow-otlp-from-platform-telemetry"
    namespace = kubernetes_namespace_v1.this[0].metadata[0].name
  }
  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name" = "opentelemetry-collector"
      }
    }
    policy_types = ["Ingress"]
    ingress {
      from {
        namespace_selector {
          match_labels = {
            "platform.refplat.org/otel-export" = "true"
          }
        }
      }
      ports {
        protocol = "TCP"
        port     = "4317"
      }
      ports {
        protocol = "TCP"
        port     = "4318"
      }
    }
  }
}

# Grafana ingress from the Cilium Gateway. The gateway's Envoy connects with the reserved Cilium
# `ingress` identity (8), which a STANDARD k8s NetworkPolicy `from:` cannot match (it's not a
# namespace/pod) — so this must be a CiliumNetworkPolicy with `fromEntities: ["ingress"]`
# (the repo's documented Gateway gotcha — see CLAUDE.md "Cilium Gateway API"). Cilium unions this
# allow with the k8s default-deny above, so Grafana is reachable only via the gateway (+ intra-ns
# scraping via allow-intra-namespace).
resource "kubernetes_manifest" "allow_grafana_from_gateway" {
  count = local.create ? 1 : 0

  manifest = {
    apiVersion = "cilium.io/v2"
    kind       = "CiliumNetworkPolicy"
    metadata = {
      name      = "allow-grafana-from-gateway"
      namespace = kubernetes_namespace_v1.this[0].metadata[0].name
    }
    spec = {
      endpointSelector = { matchLabels = { "app.kubernetes.io/name" = "grafana" } }
      ingress = [{
        fromEntities = ["ingress"]
        toPorts      = [{ ports = [{ port = "3000", protocol = "TCP" }] }]
      }]
    }
  }

  depends_on = [kubernetes_namespace_v1.this]
}

# ---------------------------------------------------------------------------
# Grafana admin credential — TF-generated (so TF owns it), mirrored to Secrets
# Manager for human retrieval, and delivered to the cluster as a k8s Secret.
# (Direct, since the secret originates in TF — ESO is for externally-sourced secrets.)
# ---------------------------------------------------------------------------
resource "random_password" "grafana_admin" {
  count   = local.create ? 1 : 0
  length  = 24
  special = false # avoid shell/URL-escaping headaches in the admin password
}

resource "aws_secretsmanager_secret" "grafana_admin" {
  count = local.create ? 1 : 0

  name        = local.grafana_admin_sm_name
  description = "Grafana admin credential (observability hub). Interim until SSO lands."
  # 0 = force-delete on destroy so a teardown→rebuild can recreate the same name; otherwise the default
  # 30-day recovery window leaves it "scheduled for deletion" and CreateSecret fails on the next bootstrap.
  recovery_window_in_days = var.secret_recovery_window_days
  tags                    = var.tags
}

resource "aws_secretsmanager_secret_version" "grafana_admin" {
  count = local.create ? 1 : 0

  secret_id = aws_secretsmanager_secret.grafana_admin[0].id
  secret_string = jsonencode({
    "admin-user"     = "admin"
    "admin-password" = random_password.grafana_admin[0].result
  })
}

resource "kubernetes_secret_v1" "grafana_admin" {
  count = local.create ? 1 : 0

  metadata {
    name      = local.grafana_admin_secret
    namespace = kubernetes_namespace_v1.this[0].metadata[0].name
    labels    = local.k8s_labels
  }
  data = {
    "admin-user"     = "admin"
    "admin-password" = random_password.grafana_admin[0].result
  }
  type = "Opaque"
}

# ---------------------------------------------------------------------------
# Curated dashboards-as-code — one ConfigMap per JSON in dashboards/, picked up by the
# Grafana sidecar (label grafana_dashboard=1). Tier-1 bundled dashboards ship with the chart;
# these are the tier-3 custom (Platform Health) + tier-2 vendored ones.
# ---------------------------------------------------------------------------
resource "kubernetes_config_map_v1" "dashboards" {
  for_each = local.create ? fileset("${path.module}/dashboards", "*.json") : toset([])

  metadata {
    name        = "obs-dashboard-${trimsuffix(each.value, ".json")}"
    namespace   = kubernetes_namespace_v1.this[0].metadata[0].name
    labels      = merge(local.k8s_labels, { grafana_dashboard = "1" })
    annotations = { grafana_folder = "Platform" }
  }
  data = {
    (each.value) = file("${path.module}/dashboards/${each.value}")
  }
}

# ---------------------------------------------------------------------------
# Alertmanager → SNS publish; AWS identity via EKS Pod Identity (ADR-047)
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "alertmanager_trust" {
  count = local.create_sns ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "alertmanager" {
  count = local.create_sns ? 1 : 0

  name_prefix        = "${var.cluster_name}-am-sns-"
  assume_role_policy = data.aws_iam_policy_document.alertmanager_trust[0].json
  tags               = var.tags
}

resource "aws_iam_role_policy" "alertmanager_sns" {
  count = local.create_sns ? 1 : 0

  name = "sns-publish"
  role = aws_iam_role.alertmanager[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "PublishAlerts"
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = [var.alerts_topic_arn]
      },
      {
        # The alerts topic is SSE-KMS encrypted (AWS-managed alias/aws/sns key),
        # so publishing requires data-key access. The managed key's ARN isn't
        # known here; scope to SNS via kms:ViaService so the grant is only usable
        # for SNS publishes in this region.
        Sid      = "EncryptAlerts"
        Effect   = "Allow"
        Action   = ["kms:GenerateDataKey*", "kms:Decrypt"]
        Resource = ["*"]
        Condition = {
          StringEquals = { "kms:ViaService" = "sns.${var.aws_region}.amazonaws.com" }
        }
      },
    ]
  })
}

resource "aws_eks_pod_identity_association" "alertmanager" {
  count = local.create_sns ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = local.alertmanager_sa
  role_arn        = aws_iam_role.alertmanager[0].arn
  tags            = var.tags
}

# ---------------------------------------------------------------------------
# P5a — Grafana CloudWatch read (Pod Identity; ADR-047 — trust pods.eks.amazonaws.com, no IRSA).
# Read-only CloudWatch + CloudWatch-Logs + tag/EC2 describe (the standard Grafana CloudWatch-datasource
# permission set; GetMetricData/ListMetrics don't support resource scoping, so Resource = "*").
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "grafana_cloudwatch_trust" {
  count = local.cloudwatch_enabled ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "grafana_cloudwatch" {
  count = local.cloudwatch_enabled ? 1 : 0

  name_prefix        = "${var.cluster_name}-graf-cw-"
  assume_role_policy = data.aws_iam_policy_document.grafana_cloudwatch_trust[0].json
  tags               = var.tags
}

resource "aws_iam_role_policy" "grafana_cloudwatch" {
  count = local.cloudwatch_enabled ? 1 : 0

  name = "cloudwatch-read"
  role = aws_iam_role.grafana_cloudwatch[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchRead"
        Effect = "Allow"
        Action = [
          "cloudwatch:DescribeAlarmsForMetric",
          "cloudwatch:DescribeAlarmHistory",
          "cloudwatch:DescribeAlarms",
          "cloudwatch:ListMetrics",
          "cloudwatch:GetMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:GetInsightRuleReport",
        ]
        Resource = ["*"]
      },
      {
        Sid    = "CloudWatchLogsRead"
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups",
          "logs:GetLogGroupFields",
          "logs:StartQuery",
          "logs:StopQuery",
          "logs:GetQueryResults",
          "logs:GetLogEvents",
        ]
        Resource = ["*"]
      },
      {
        Sid    = "ResourceTagAndEC2Describe"
        Effect = "Allow"
        Action = [
          "tag:GetResources",
          "ec2:DescribeTags",
          "ec2:DescribeInstances",
          "ec2:DescribeRegions",
        ]
        Resource = ["*"]
      },
    ]
  })
}

resource "aws_eks_pod_identity_association" "grafana_cloudwatch" {
  count = local.cloudwatch_enabled ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = local.grafana_service # chart names the SA <release>-grafana
  role_arn        = aws_iam_role.grafana_cloudwatch[0].arn
  tags            = var.tags
}

# ---------------------------------------------------------------------------
# kube-prometheus-stack
# ---------------------------------------------------------------------------
resource "helm_release" "kube_prometheus_stack" {
  count = local.create ? 1 : 0

  name             = var.helm_release_name
  repository       = var.helm_repository
  chart            = var.helm_chart
  version          = var.helm_chart_version
  namespace        = kubernetes_namespace_v1.this[0].metadata[0].name
  create_namespace = false # created above with the PSA label
  timeout          = var.helm_timeout
  wait             = var.helm_wait
  atomic           = var.helm_wait
  cleanup_on_fail  = true

  values = [
    yamlencode(local.helm_values),
  ]

  depends_on = [
    kubernetes_secret_v1.grafana_admin,
    kubernetes_network_policy_v1.default_deny_ingress,
    aws_iam_role_policy.alertmanager_sns,
    kubernetes_manifest.alertmanager_slack_webhook,
    kubernetes_manifest.alertmanager_pagerduty,
    kubernetes_manifest.alertmanager_healthchecks,
    kubernetes_manifest.grafana_oidc_secret,
    aws_eks_pod_identity_association.grafana_cloudwatch,
    aws_eks_pod_identity_association.alertmanager,
  ]
}

# ---------------------------------------------------------------------------
# Slack webhook for Alertmanager — External Secret synced from AWS Secrets Manager.
# Mounted into Alertmanager via alertmanagerSpec.secrets; the Slack receiver reads it through
# api_url_file, so the webhook URL never enters Terraform state or the helm values. The SM secret is
# created manually (the URL is generated in Slack), JSON property "url".
# ---------------------------------------------------------------------------

resource "kubernetes_manifest" "alertmanager_slack_webhook" {
  count = local.slack_enabled ? 1 : 0

  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "alertmanager-slack-webhook"
      namespace = var.namespace
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef  = { name = var.secret_store_name, kind = "ClusterSecretStore" }
      target          = { name = "alertmanager-slack-webhook", creationPolicy = "Owner" }
      data = [{
        secretKey = "url"
        remoteRef = { key = var.slack_webhook_secret_name, property = "url" }
      }]
    }
  }

  depends_on = [kubernetes_namespace_v1.this]
}

# ---------------------------------------------------------------------------
# PagerDuty routing key for Alertmanager — External Secret synced from AWS Secrets Manager.
# Mounted via alertmanagerSpec.secrets; the PagerDuty receiver reads it through routing_key_file. The SM
# secret is created manually (the key is generated in PagerDuty), JSON property "routingKey".
# ---------------------------------------------------------------------------

resource "kubernetes_manifest" "alertmanager_pagerduty" {
  count = local.pagerduty_enabled ? 1 : 0

  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "alertmanager-pagerduty"
      namespace = var.namespace
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef  = { name = var.secret_store_name, kind = "ClusterSecretStore" }
      target          = { name = "alertmanager-pagerduty", creationPolicy = "Owner" }
      data = [{
        secretKey = "routingKey"
        remoteRef = { key = var.pagerduty_routing_key_secret_name, property = "routingKey" }
      }]
    }
  }

  depends_on = [kubernetes_namespace_v1.this]
}

# Dead-man's switch ping URL, synced from Secrets Manager. The SM secret MUST exist before this is enabled
# (creationPolicy Owner + the Alertmanager mount) — else the ExternalSecret can't sync and Alertmanager fails
# to start. See the healthchecks_ping_url_secret_name variable's activation note.
resource "kubernetes_manifest" "alertmanager_healthchecks" {
  count = local.deadman_enabled ? 1 : 0

  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "alertmanager-healthchecks"
      namespace = var.namespace
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef  = { name = var.secret_store_name, kind = "ClusterSecretStore" }
      target          = { name = "alertmanager-healthchecks", creationPolicy = "Owner" }
      data = [{
        secretKey = "pingUrl"
        remoteRef = { key = var.healthchecks_ping_url_secret_name, property = "pingUrl" }
      }]
    }
  }

  depends_on = [kubernetes_namespace_v1.this]
}

# ---------------------------------------------------------------------------
# Grafana SSO (#592) — Keycloak OIDC client secret synced from AWS Secrets Manager, plus the gateway-ClusterIP
# lookup backing the split-horizon host-alias. The secret (keycloak-config writes platform/keycloak/grafana-oidc)
# syncs to the `grafana-oidc` K8s secret, injected as GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET. Mirrors ArgoCD/Backstage.
# ---------------------------------------------------------------------------

resource "kubernetes_manifest" "grafana_oidc_secret" {
  count = local.grafana_oidc_enabled ? 1 : 0

  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = local.grafana_oidc_secret
      namespace = var.namespace
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef  = { name = var.secret_store_name, kind = "ClusterSecretStore" }
      target          = { name = local.grafana_oidc_secret, creationPolicy = "Owner" }
      data = [{
        secretKey = "client-secret"
        remoteRef = { key = var.grafana_oidc_secret_manager_key, property = "client-secret" }
      }]
    }
  }

  depends_on = [kubernetes_namespace_v1.this]
}

# Current ClusterIP of the shared Cilium gateway Service — backs the OIDC issuer host-alias (never hardcoded;
# self-corrects on apply if the gateway Service is recreated). Mirrors the Backstage module.
data "kubernetes_service_v1" "gateway" {
  count = local.grafana_oidc_alias_on ? 1 : 0

  metadata {
    name      = var.gateway_service_name
    namespace = var.gateway_service_namespace
  }
}
