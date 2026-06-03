locals {
  create = var.create

  # Sanitize tags for K8s label compliance (RFC 1123): lowercase, valid chars, max 63 chars.
  k8s_labels = {
    for k, v in var.tags :
    replace(lower(k), "/[^a-z0-9_.-]/", "_") => replace(lower(v), "/[^a-z0-9_.-]/", "_")
    if length(replace(lower(k), "/[^a-z0-9_.-]/", "_")) <= 63 && length(replace(lower(v), "/[^a-z0-9_.-]/", "_")) <= 63
  }

  cnpg_values = {
    replicaCount = var.replica_count
    podLabels    = local.k8s_labels

    # EKS + Cilium overlay (cluster-pool): the EKS managed control plane can't route to overlay pod IPs,
    # so the operator's admission webhook server runs on hostNetwork (node VPC IP). On hostNetwork the
    # webhook port becomes a HOST port — move it off 9443 to avoid colliding with kyverno's admission
    # controller (host 9443) and cleanup controller (9444). 9446 is unused by the platform's hostNetwork
    # webhooks. ClusterFirstWithHostNet keeps cluster DNS working for the operator on hostNetwork.
    hostNetwork = var.webhook_host_network
    dnsPolicy   = var.webhook_host_network ? "ClusterFirstWithHostNet" : ""
    webhook = {
      port = var.webhook_host_network ? 9446 : 9443
    }

    # On hostNetwork the operator's metrics server (controller-runtime default :8080) also binds a HOST
    # port, which collides with other node processes/hostNetwork pods on 8080 (the operator crashloops:
    # "listen tcp :8080: bind: address already in use"). We don't scrape CNPG metrics yet and the
    # readiness probe targets the webhook server (not metrics), so disable it (--metrics-bind-address=0).
    # Re-enable on a free host port when wiring CNPG into the observability hub (#102).
    additionalArgs = var.webhook_host_network ? ["--metrics-bind-address=0"] : []
  }
}

resource "helm_release" "cloudnative_pg" {
  count            = local.create ? 1 : 0
  name             = var.helm_release_name
  repository       = var.helm_repository
  chart            = var.helm_chart
  version          = var.helm_chart_version
  namespace        = var.namespace
  create_namespace = true
  timeout          = var.helm_timeout
  wait             = var.helm_wait
  atomic           = var.helm_wait
  cleanup_on_fail  = true
  replace          = true

  values = [yamlencode(local.cnpg_values)]
}
