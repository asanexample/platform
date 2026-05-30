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
resource "kubernetes_cluster_role" "platform_operator" {
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

  # Debug: read Kyverno PolicyReports + policies — the primary surface for
  # understanding WHY a resource was admitted/rejected (e.g. verifyImages
  # signature/attestation results). Read-only; AmazonEKSViewPolicy's view role
  # doesn't cover these CRD groups, and authoring stays in GitOps (ADR-040).
  rule {
    api_groups = ["wgpolicyk8s.io"]
    resources  = ["policyreports", "clusterpolicyreports"]
    verbs      = ["get", "list", "watch"]
  }
  rule {
    api_groups = ["kyverno.io"]
    resources  = ["policies", "clusterpolicies", "policyexceptions"]
    verbs      = ["get", "list", "watch"]
  }
  rule {
    api_groups = ["reports.kyverno.io"]
    resources  = ["ephemeralreports", "clusterephemeralreports"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding" "platform_operator" {
  count = local.create ? 1 : 0

  metadata {
    name   = "platform-operator"
    labels = { "app.kubernetes.io/managed-by" = "terraform" }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.platform_operator[0].metadata[0].name
  }

  subject {
    kind      = "Group"
    name      = var.group_name
    api_group = "rbac.authorization.k8s.io"
  }
}
