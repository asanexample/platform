locals {
  create = var.create

  # Audit rollout keeps the webhook fail-open (Ignore) so a policy/engine problem can never block
  # admission; only once Enforce + HA are proven do we fail-closed (Fail).
  failure_policy = var.validation_failure_action == "Enforce" ? "Fail" : "Ignore"

  # Sanitize tags for K8s label compliance (RFC 1123): lowercase, valid chars, max 63 chars
  k8s_labels = {
    for k, v in var.tags :
    replace(lower(k), "/[^a-z0-9_.-]/", "_") => replace(lower(v), "/[^a-z0-9_.-]/", "_")
    if length(replace(lower(k), "/[^a-z0-9_.-]/", "_")) <= 63 && length(replace(lower(v), "/[^a-z0-9_.-]/", "_")) <= 63
  }

  # Engine (kyverno chart) values — HA admission controller, dedicated namespace, default
  # resourceFilters (which already skip kube-system + the kyverno namespace) left intact for the
  # background scanner; per-policy excludes handle the remaining infra namespaces.
  engine_values = {
    admissionController = {
      replicas  = var.replica_count
      podLabels = local.k8s_labels
    }
    # Leader-elected controllers: a single active replica regardless of count.
    backgroundController = { replicas = 1 }
    reportsController    = { replicas = 1 }
    cleanupController    = { replicas = 1 }
  }

  # Policies (local chart) values — all dynamic, environment-specific knobs live here so the module
  # carries no team-specific data.
  policies_values = {
    validationFailureAction = var.validation_failure_action
    failurePolicy           = local.failure_policy
    complianceTier          = var.compliance_tier
    allowedRegistries       = var.allowed_registries
    tenantRegistryMap       = var.tenant_registry_map
    excludeNamespaces       = var.exclude_namespaces
    excludePrincipals       = var.exclude_principals
    tenantNamespaceLabel    = var.tenant_namespace_label
    requiredWorkloadLabels  = var.required_workload_labels
    enableMutateDefaults    = var.enable_mutate_defaults
    additionalPolicies      = var.additional_policies
    commonLabels            = local.k8s_labels
  }
}

# ---------------------------------------------------------------------------
# Kyverno engine
# ---------------------------------------------------------------------------

resource "helm_release" "kyverno" {
  count            = local.create ? 1 : 0
  name             = "kyverno"
  repository       = var.helm_repository
  chart            = "kyverno"
  version          = var.helm_chart_version
  namespace        = var.namespace
  create_namespace = true
  timeout          = var.helm_timeout
  wait             = var.helm_wait
  atomic           = var.helm_wait
  cleanup_on_fail  = true

  values = [
    yamlencode(local.engine_values),
  ]
}

# ---------------------------------------------------------------------------
# Platform ClusterPolicies (bundled local chart)
# ---------------------------------------------------------------------------
# Delivered as a second Helm release rather than kubernetes_manifest resources: a local chart needs
# no plan-time access to the Kyverno CRDs (which the engine release above installs in the same
# apply), avoiding the kubernetes_manifest chicken-and-egg. depends_on guarantees CRDs exist first.

resource "helm_release" "policies" {
  count           = local.create ? 1 : 0
  name            = "kyverno-platform-policies"
  chart           = "${path.module}/policies-chart"
  namespace       = var.namespace
  timeout         = var.helm_timeout
  wait            = var.helm_wait
  atomic          = var.helm_wait
  cleanup_on_fail = true

  values = [
    yamlencode(local.policies_values),
  ]

  depends_on = [helm_release.kyverno]
}
