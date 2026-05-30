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

      # Pod Security Admission. enforce=baseline blocks the node-escape vectors
      # (privileged, hostPath, hostNetwork/PID, host ports); warn/audit=restricted
      # surface stricter violations without breaking current workloads.
      "pod-security.kubernetes.io/enforce" = "baseline"
      "pod-security.kubernetes.io/warn"    = "restricted"
      "pod-security.kubernetes.io/audit"   = "restricted"
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

      # Caps on shared-capacity object types (noisy-neighbor protection).
      services                 = each.value.resource_quota.services
      "services.loadbalancers" = each.value.resource_quota.loadbalancers
      persistentvolumeclaims   = each.value.resource_quota.pvcs
      "requests.storage"       = each.value.resource_quota.storage
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

# Allows egress to the EKS Pod Identity agent so tenant pods can fetch their workload AWS credentials
# (ADR-041). The agent serves credentials at the link-local 169.254.170.23:80, which is node-served, so
# Cilium classifies it as the `host` entity. A CIDR rule (broad 0.0.0.0/0 OR a narrow /32) does NOT match
# the host entity in Cilium, so we must allow it via `toEntities: [host]`, scoped to port 80. This also
# makes IMDS (169.254.169.254:80, also host) network-reachable — but the node enforces IMDSv2 with
# HttpPutResponseHopLimit=1, so a pod (1 hop from the node) cannot reach IMDS regardless. That hop-limit
# is the hard control against node-role theft; the egress restriction is defense-in-depth. (Verify the
# hop-limit stays 1 on the node groups.) Rendered for every namespace tenant; harmless without an association.
resource "kubernetes_manifest" "tenant_allow_pod_identity_egress" {
  for_each = local.namespace_tenants

  manifest = {
    apiVersion = "cilium.io/v2"
    kind       = "CiliumNetworkPolicy"
    metadata = {
      name      = "allow-pod-identity-egress"
      namespace = kubernetes_namespace.tenant[each.key].metadata[0].name
    }
    spec = {
      endpointSelector = {}
      egress = [{
        toEntities = ["host"]
        toPorts = [{
          ports = [{ port = "80", protocol = "TCP" }]
        }]
      }]
    }
  }
}

# Allows DNS resolution (port 53) and all other egress. Named "allow-dns" because
# DNS is the primary concern — without it, pods cannot resolve service names.
# General egress is also permitted as the default tenant posture, EXCEPT the
# instance metadata endpoint (169.254.169.254) — blocking it stops a tenant pod
# from stealing the node IAM role's credentials.
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
          cidr   = "0.0.0.0/0"
          except = ["169.254.169.254/32"]
        }
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Developer RBAC (group-mapped from per-team EKS access entries)
# ---------------------------------------------------------------------------

# Cluster-wide role equivalent to the built-in "edit" role, under a name we own
# so its permissions can be tightened per compliance tier (e.g. exclude secrets)
# without touching the per-namespace bindings. Created once for the cluster.
resource "kubernetes_cluster_role" "tenant_developer" {
  count = local.create && length(local.namespace_tenants) > 0 ? 1 : 0

  metadata {
    name   = "tenant-developer"
    labels = { "app.kubernetes.io/managed-by" = "terraform" }
  }

  aggregation_rule {
    cluster_role_selectors {
      match_labels = { "rbac.authorization.k8s.io/aggregate-to-edit" = "true" }
    }
  }
}

# Binds each team's developer group to tenant-developer within that team's
# namespace only. The group name (team-<name>:developers) must match the
# kubernetes_groups set on the team's EKS access entry in the eks unit.
resource "kubernetes_role_binding" "tenant_developers" {
  for_each = local.namespace_tenants

  metadata {
    name      = "tenant-developers"
    namespace = kubernetes_namespace.tenant[each.key].metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.tenant_developer[0].metadata[0].name
  }

  subject {
    kind      = "Group"
    name      = "team-${each.key}:developers"
    api_group = "rbac.authorization.k8s.io"
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
