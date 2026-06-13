locals {
  create = var.create
}

# ---------------------------------------------------------------------------
# Platform operator RBAC
# ---------------------------------------------------------------------------

# Cluster-wide read for PlatformAdmin comes from the AmazonEKSViewPolicy access
# entry on that principal. This ClusterRole adds ONLY the debug + operate verbs
# View lacks, and deliberately grants no `create` and no other resource types —
# resource authoring flows through GitOps (ArgoCD), emergencies via break-glass.
# See ADR-040.
resource "kubernetes_cluster_role_v1" "platform_operator" {
  count = local.create ? 1 : 0

  metadata {
    name   = "platform-operator"
    labels = { "app.kubernetes.io/managed-by" = "terraform" }
  }

  # Debug: read logs, exec/attach a shell, port-forward.
  rule {
    api_groups = [""]
    resources  = ["pods/log"]
    verbs      = ["get"]
  }
  rule {
    api_groups = [""]
    resources  = ["pods/exec", "pods/portforward"]
    verbs      = ["create"]
  }

  # Operate: delete a stuck pod; evict pods when draining a node.
  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["delete"]
  }
  rule {
    # Eviction subresource is registered under both core and policy groups
    # depending on cluster version; allow both so `kubectl drain` works.
    api_groups = ["", "policy"]
    resources  = ["pods/eviction"]
    verbs      = ["create"]
  }

  # Operate: cordon / drain / uncordon nodes (patches spec.unschedulable). Read
  # verbs are required too — AmazonEKSViewPolicy does not grant cluster-scoped
  # node read, and `kubectl drain`/`cordon` must get the node first.
  rule {
    api_groups = [""]
    resources  = ["nodes"]
    verbs      = ["get", "list", "watch", "patch"]
  }

  # Operate: `kubectl rollout restart` (patches a restartedAt annotation).
  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "statefulsets", "daemonsets"]
    verbs      = ["patch"]
  }

  # Debug: cluster-wide READ on EVERYTHING, including custom resources. The
  # AmazonEKSViewPolicy access entry only reads the fixed built-in resource set
  # (like the `view` role), so it can't read CRDs — crossplane (XTenant,
  # ProviderConfig, ProviderConfigUsage, Provider), tailscale (Connector),
  # cnpg (Cluster), kyverno (PolicyReports) — which is exactly what an operator
  # needs to debug a stuck reconcile/teardown (e.g. which finalizer is blocking
  # deletion). Read-only: get/list/watch, no authoring (that stays in GitOps,
  # ADR-040). Note `view` deliberately omits Secrets, but this role already has
  # pods/exec — an operator can read any mounted secret by execing into its pod —
  # so withholding Secret GET here is no real boundary; granting it directly just
  # makes debugging honest. This supersedes the old per-CRD-group read rules.
  rule {
    api_groups = ["*"]
    resources  = ["*"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "platform_operator" {
  count = local.create ? 1 : 0

  metadata {
    name   = "platform-operator"
    labels = { "app.kubernetes.io/managed-by" = "terraform" }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.platform_operator[0].metadata[0].name
  }

  subject {
    kind      = "Group"
    name      = var.group_name
    api_group = "rbac.authorization.k8s.io"
  }
}
