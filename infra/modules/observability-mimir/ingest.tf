# ---------------------------------------------------------------------------
# Cross-cluster spoke ingest edge (P10) — Gateway-API-native, no proxy.
# Per spoke: a write-only HTTPRoute on the shared Cilium Gateway that FORCE-SETS X-Scope-OrgID to the
# mapped tenant (overwriting any client value — so a spoke can't spoof another tenant, the ADR-044 guard)
# and routes only /api/v1/push (no query path is exposed cross-cluster). The header-overwrite + path-match
# are native Gateway API filters — same idiom the repo already uses for HTTP→HTTPS redirects. Auth is
# network isolation (the internal NLB reachable only over the VPC/TGW); mTLS is the P10.x hardening follow-up.
# ---------------------------------------------------------------------------

resource "kubernetes_manifest" "spoke_ingest_route" {
  for_each = local.spoke_ingest_create ? var.spoke_ingest.tenants : {}

  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "${var.helm_release_name}-spoke-${each.key}"
      namespace = var.namespace
    }
    spec = {
      parentRefs = [{
        name        = var.spoke_ingest.gateway_name
        namespace   = var.spoke_ingest.gateway_namespace
        sectionName = "https"
      }]
      hostnames = ["${each.key}-mimir.${var.spoke_ingest.domain}"]
      # Each rule force-SETS X-Scope-OrgID to this route's tenant, overwriting any client header — so the spoke
      # can only ever touch its OWN tenant. The push rule is always present; the read rule (/prometheus) is
      # added only for prefixes opted into query_tenants (W8c: spoke-side metric-gated canary).
      rules = concat(
        [{
          matches     = [{ path = { type = "PathPrefix", value = "/api/v1/push" } }]
          filters     = [{ type = "RequestHeaderModifier", requestHeaderModifier = { set = [{ name = "X-Scope-OrgID", value = each.value }] } }]
          backendRefs = [{ name = "${var.helm_release_name}-gateway", port = 80 }]
          }, {
          # OTLP metrics write path (P10 / P14) — Mimir's native OTLP ingest, which the gateway nginx already
          # proxies to the distributor (`/otlp/v1/metrics`). Lets a spoke's OTel collector push app-SDK metrics
          # (otlphttp exporter) with the tenant force-set, exactly like the Prometheus /api/v1/push path — so a
          # tenant workload's RED metrics (http_server_request_duration_*) land in this spoke's own Mimir tenant.
          matches     = [{ path = { type = "PathPrefix", value = "/otlp/v1/metrics" } }]
          filters     = [{ type = "RequestHeaderModifier", requestHeaderModifier = { set = [{ name = "X-Scope-OrgID", value = each.value }] } }]
          backendRefs = [{ name = "${var.helm_release_name}-gateway", port = 80 }]
        }],
        contains(var.spoke_ingest.query_tenants, each.key) ? [{
          # Read path — Mimir's Prometheus query API (/prometheus/api/v1/{query,query_range,series,labels,...}).
          # Same tenant force-set, so reads are scoped to this spoke's OWN data.
          matches     = [{ path = { type = "PathPrefix", value = "/prometheus" } }]
          filters     = [{ type = "RequestHeaderModifier", requestHeaderModifier = { set = [{ name = "X-Scope-OrgID", value = each.value }] } }]
          backendRefs = [{ name = "${var.helm_release_name}-gateway", port = 80 }]
        }] : []
      )
    }
  }
}

# The Gateway's Envoy connects with the reserved Cilium `ingress` identity (8), which a STANDARD k8s
# NetworkPolicy `from:` can't match — so admit it to the Mimir gateway via a CiliumNetworkPolicy
# (the repo's documented Gateway gotcha; mirrors `allow-grafana-from-gateway` in the observability module).
# Ports omitted: the gateway pod's nginx targetPort isn't worth hardcoding — the `ingress` entity is the
# trusted Envoy, and the default-deny + this single allow already scope who reaches the gateway pods.
resource "kubernetes_manifest" "spoke_ingest_from_gateway" {
  count = local.spoke_ingest_create ? 1 : 0

  manifest = {
    apiVersion = "cilium.io/v2"
    kind       = "CiliumNetworkPolicy"
    metadata = {
      name      = "${var.helm_release_name}-spoke-ingest-from-gateway"
      namespace = var.namespace
    }
    spec = {
      endpointSelector = {
        matchLabels = {
          "app.kubernetes.io/name"      = var.helm_release_name
          "app.kubernetes.io/component" = "gateway"
        }
      }
      ingress = [{ fromEntities = ["ingress"] }]
    }
  }
}

# P13 per-team dual-write ingest (#590) — an ADDITIONAL write route to cortex-tenant. Unlike the force-stamped
# spoke route above, this STRIPS any inbound X-Scope-OrgID and forwards to cortex-tenant, which derives the
# tenant per-series from the agent-set `route_tenant` label and splits into per-team tenants. Additive: the
# spoke keeps its force-stamped `<prefix>-mimir` route, so the `preprod` tenant + all its consumers are
# unchanged; this second route just lands a per-team copy. Plus the Cilium allow (the ns default-denies).
resource "kubernetes_manifest" "cortex_tenant_ingest_route" {
  count = local.create && var.spoke_ingest.cortex_tenant_route != null ? 1 : 0

  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "${var.helm_release_name}-cortex-tenant-ingest"
      namespace = var.namespace
    }
    spec = {
      parentRefs = [{
        name        = var.spoke_ingest.gateway_name
        namespace   = var.spoke_ingest.gateway_namespace
        sectionName = "https"
      }]
      hostnames = ["${var.spoke_ingest.cortex_tenant_route.hostname_prefix}.${var.spoke_ingest.domain}"]
      rules = [{
        matches = [{ path = { type = "PathPrefix", value = "/push" } }]
        # Strip any inbound X-Scope-OrgID — the tenant comes from the per-series route_tenant label, NOT a
        # client header (anti-spoof: a spoke can't pick its own tenant header; cortex-tenant owns assignment).
        filters     = [{ type = "RequestHeaderModifier", requestHeaderModifier = { remove = ["X-Scope-OrgID"] } }]
        backendRefs = [{ name = var.spoke_ingest.cortex_tenant_route.service_name, port = var.spoke_ingest.cortex_tenant_route.service_port }]
      }]
    }
  }
}

resource "kubernetes_manifest" "cortex_tenant_ingest_from_gateway" {
  count = local.create && var.spoke_ingest.cortex_tenant_route != null ? 1 : 0

  manifest = {
    apiVersion = "cilium.io/v2"
    kind       = "CiliumNetworkPolicy"
    metadata = {
      name      = "${var.helm_release_name}-cortex-tenant-ingest-from-gateway"
      namespace = var.namespace
    }
    spec = {
      endpointSelector = {
        matchLabels = { "app.kubernetes.io/name" = var.spoke_ingest.cortex_tenant_route.service_name }
      }
      ingress = [{ fromEntities = ["ingress"] }]
    }
  }
}

# Direct in-cluster query consumers (ADR-091 A3): admit named namespaces (e.g. backstage's Cost tab) to the
# Mimir gateway's query API. The ns default-denies ingress, so this Cilium allow is what lets them query.
resource "kubernetes_manifest" "query_from_namespaces" {
  count = local.create && length(var.query_consumer_namespaces) > 0 ? 1 : 0

  manifest = {
    apiVersion = "cilium.io/v2"
    kind       = "CiliumNetworkPolicy"
    metadata = {
      name      = "${var.helm_release_name}-query-from-namespaces"
      namespace = var.namespace
    }
    spec = {
      endpointSelector = {
        matchLabels = {
          "app.kubernetes.io/name"      = var.helm_release_name
          "app.kubernetes.io/component" = "gateway"
        }
      }
      ingress = [{
        fromEndpoints = [
          for ns in var.query_consumer_namespaces :
          { matchLabels = { "k8s:io.kubernetes.pod.namespace" = ns } }
        ]
      }]
    }
  }
}
