locals {
  create       = var.create
  blackbox_svc = "blackbox-exporter"

  # Map the probe hostnames → the Cilium Gateway ClusterIP via pod hostAliases, so the exporter reaches
  # Envoy directly (no internal-NLB hairpin) while the probe URLs stay the real hostnames (TLS SNI + Host
  # still verify against the real cert). Skipped when no gateway service is given (then probes go via DNS/NLB).
  use_gateway_alias  = local.create && var.gateway_service_name != "" && length(var.probe_targets) > 0
  probe_hostnames    = [for t in var.probe_targets : trimprefix(trimprefix(t, "https://"), "http://")]
  gateway_cluster_ip = try(data.kubernetes_service_v1.gateway[0].spec[0].cluster_ip, "")
  host_aliases = local.use_gateway_alias && local.gateway_cluster_ip != "" ? [{
    ip = local.gateway_cluster_ip
    # NB: this chart's template ranges over `.hostNames` (camelCase), not the k8s-standard `hostnames`.
    hostNames = local.probe_hostnames
  }] : []

  # ---- blackbox-exporter helm values ----
  helm_values = {
    fullnameOverride = local.blackbox_svc
    hostAliases      = local.host_aliases

    # A single module for the platform's HTTPS endpoints: GET, TLS verified (real Let's Encrypt cert),
    # treat redirect-to-login / auth-required as "up" (the gateway + TLS are healthy even if the app 302s).
    config = {
      modules = {
        http_platform = {
          prober  = "http"
          timeout = var.probe_timeout
          http = {
            method                = "GET"
            valid_status_codes    = var.valid_status_codes
            fail_if_not_ssl       = true # these are https — a plaintext response is a failure
            preferred_ip_protocol = "ip4"
            tls_config            = { insecure_skip_verify = false } # verify the cert (catches expiry/chain breaks)
          }
        }
      }
    }

    # We scrape via Probe CRs (per-target), not a ServiceMonitor on the exporter itself.
    serviceMonitor = { enabled = false }

    resources = {
      requests = { cpu = "20m", memory = "32Mi" }
      limits   = { memory = "64Mi" }
    }
  }
}

# Read the Cilium Gateway Service ClusterIP (for the hostAlias rewrite above).
data "kubernetes_service_v1" "gateway" {
  count = local.create && var.gateway_service_name != "" ? 1 : 0

  metadata {
    name      = var.gateway_service_name
    namespace = var.gateway_service_namespace
  }
}

# ---------------------------------------------------------------------------
# Helm release — prometheus-blackbox-exporter
# ---------------------------------------------------------------------------

resource "helm_release" "blackbox" {
  count = local.create ? 1 : 0

  name             = "blackbox-exporter"
  repository       = var.helm_repository
  chart            = "prometheus-blackbox-exporter"
  version          = var.helm_chart_version
  namespace        = var.namespace
  create_namespace = false
  timeout          = var.helm_timeout
  wait             = var.helm_wait
  atomic           = var.helm_wait
  cleanup_on_fail  = true

  values = [yamlencode(local.helm_values)]
}

# ---------------------------------------------------------------------------
# Probe CR — the hub Prometheus (probeSelectorNilUsesHelmValues=false) discovers this and scrapes the
# blackbox-exporter once per target, producing external probe_* metrics → Mimir. The Probe CRD ships with
# the prometheus-operator (P1), so kubernetes_manifest is fine here (no CRD-at-plan-time issue).
# ---------------------------------------------------------------------------

resource "kubernetes_manifest" "probe" {
  count = local.create && length(var.probe_targets) > 0 ? 1 : 0

  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "Probe"
    metadata = {
      name      = "platform-endpoints"
      namespace = var.namespace
    }
    spec = {
      jobName  = "blackbox-platform"
      interval = var.probe_interval
      module   = "http_platform"
      prober = {
        url = "${local.blackbox_svc}:9115"
      }
      targets = {
        staticConfig = {
          static = var.probe_targets
        }
      }
    }
  }

  depends_on = [helm_release.blackbox]
}
