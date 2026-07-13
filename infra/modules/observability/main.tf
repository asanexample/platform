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
