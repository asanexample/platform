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
