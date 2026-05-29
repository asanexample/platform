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
      # Opinionated platform defaults — applied to containers without explicit resource specs
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

# K8s NetworkPolicy allows traffic from gateway and kube-system namespaces.
# The companion CiliumNetworkPolicy below is also required because Cilium's
# Envoy proxy uses the L3 "ingress" identity, which is not expressible as a
# K8s NetworkPolicy namespaceSelector.
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
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "kube-system"
          }
        }
      }
    }
  }
}

resource "kubernetes_manifest" "tenant_allow_gateway_envoy" {
  for_each = local.namespace_tenants

  manifest = {
    apiVersion = "cilium.io/v2"
    kind       = "CiliumNetworkPolicy"
    metadata = {
      name      = "allow-gateway-envoy"
      namespace = kubernetes_namespace.tenant[each.key].metadata[0].name
    }
    spec = {
      endpointSelector = {}
      ingress = [{
        # "ingress" = Cilium Gateway Envoy proxy (identity 8)
        # "remote-node" = cross-node traffic (pods scheduled on different nodes)
        # "host" = kubelet health checks
        fromEntities = ["ingress", "remote-node", "host"]
      }]
    }
  }
}

# Allows DNS resolution (port 53) and all other egress. Named "allow-dns" because
# DNS is the primary concern — without it, pods cannot resolve service names.
# General egress is also permitted as the default tenant posture.
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

  chart_version       = var.vcluster_chart_version
  storage_class       = var.vcluster_storage_class
  persistence_enabled = var.vcluster_persistence_enabled

  policies = {
    network_policy = true
    limit_range    = true
    resource_quota = true
  }

  tags = var.tags
}
