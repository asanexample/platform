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
    # Target label MUST match observability-cortex-tenant's routing_label (`route_tenant`) — deliberately
    # NOT `tenant`, which Mimir/Loki already emit as a meaningful per-tenant self-metric dimension (routing
    # on that name would clobber + strip it). cortex-tenant strips route_tenant after routing, so it is
    # never stored; the native `tenant` label is left untouched.
    writeRelabelConfigs = local._per_team_write ? [
      { sourceLabels = ["namespace"], regex = ".*", targetLabel = "route_tenant", replacement = "platform" },
      { sourceLabels = ["namespace"], regex = "([a-z0-9]+)-[a-z0-9-]+-(dev|test|uat|staging|prod)", targetLabel = "route_tenant", replacement = "$1" },
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
        # Trace -> profiles span link (P8b, #1269): unlike trace->logs/metrics (GA), the Tempo datasource's
        # `tracesToProfiles` "Related profiles" link is still gated behind this feature toggle in Grafana 13 —
        # without it the link is silently omitted from a span's Links menu even with a valid config. Confirmed
        # ABSENT via /api/frontend/settings before enabling.
        feature_toggles = { enable = "traceToProfiles" }
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
