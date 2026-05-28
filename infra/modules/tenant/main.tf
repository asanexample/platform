locals {
  create = var.create

  namespace_tenants = { for k, v in var.tenants : k => v if v.mode == "namespace" && local.create }
  vcluster_tenants  = { for k, v in var.tenants : k => v if v.mode == "vcluster" && local.create }
}

# ---------------------------------------------------------------------------
# Namespace-mode tenants
# ---------------------------------------------------------------------------

resource "kubernetes_namespace" "tenant" {
  for_each = local.namespace_tenants

  metadata {
    name = "team-${each.key}"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "platform.refplat.org/tenant"  = each.key
      "platform.refplat.org/mode"    = "namespace"
    }
  }
}

resource "kubernetes_resource_quota" "tenant" {
  for_each = local.namespace_tenants

  metadata {
    name      = "tenant-quota"
    namespace = kubernetes_namespace.tenant[each.key].metadata[0].name
  }

  spec {
    hard = {
      "requests.cpu"    = each.value.resource_quota.cpu
      "requests.memory" = each.value.resource_quota.memory
      "limits.cpu"      = each.value.resource_quota.cpu
      "limits.memory"   = each.value.resource_quota.memory
      pods              = each.value.resource_quota.pods
    }
  }
}

resource "kubernetes_limit_range" "tenant" {
  for_each = local.namespace_tenants

  metadata {
    name      = "tenant-limits"
    namespace = kubernetes_namespace.tenant[each.key].metadata[0].name
  }

  spec {
    limit {
      type = "Container"
      default = {
        cpu    = "500m"
        memory = "512Mi"
      }
      default_request = {
        cpu    = "100m"
        memory = "128Mi"
      }
    }
  }
}

resource "kubernetes_network_policy" "tenant_default_deny" {
  for_each = local.namespace_tenants

  metadata {
    name      = "default-deny-ingress"
    namespace = kubernetes_namespace.tenant[each.key].metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress"]
  }
}

resource "kubernetes_network_policy" "tenant_allow_gateway" {
  for_each = local.namespace_tenants

  metadata {
    name      = "allow-gateway-ingress"
    namespace = kubernetes_namespace.tenant[each.key].metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress"]

    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = var.gateway_namespace
          }
        }
      }
    }
  }
}

resource "kubernetes_network_policy" "tenant_allow_dns" {
  for_each = local.namespace_tenants

  metadata {
    name      = "allow-dns-egress"
    namespace = kubernetes_namespace.tenant[each.key].metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Egress"]

    egress {
      ports {
        port     = "53"
        protocol = "UDP"
      }
      ports {
        port     = "53"
        protocol = "TCP"
      }
    }

    egress {
      to {
        ip_block {
          cidr = "0.0.0.0/0"
        }
      }
    }
  }
}

# ---------------------------------------------------------------------------
# vCluster-mode tenants
# ---------------------------------------------------------------------------

module "vcluster" {
  source   = "../vcluster"
  for_each = local.vcluster_tenants

  create       = true
  cluster_name = each.key
  namespace    = "vc-${each.key}"
  environment  = var.environment
  region_abbv  = var.region_abbv

  chart_version = var.vcluster_chart_version

  isolation = {
    network_policy = true
    limit_range    = { enabled = true }
    resource_quota = { enabled = true }
  }

  custom_resource_sync = [
    {
      group   = "gateway.networking.k8s.io"
      version = "v1"
      kind    = "HTTPRoute"
    },
  ]

  tags = var.tags
}
