locals {
  create = var.create

  # Audit rollout keeps the webhook fail-open (Ignore) so a policy/engine problem can never block
  # admission; only once Enforce + HA are proven do we fail-closed (Fail).
  failure_policy        = var.validation_failure_action == "Enforce" ? "Fail" : "Ignore"
  verify_failure_policy = var.verify_failure_action == "Enforce" ? "Fail" : "Ignore"
  attest_failure_policy = var.attest_failure_action == "Enforce" ? "Fail" : "Ignore"

  # Kyverno needs ECR read (IRSA) to fetch cosign signatures for verifyImages (Phase 3).
  create_irsa = local.create && var.enable_image_verification && var.oidc_provider_arn != ""
  irsa_sa_annotations = local.create_irsa ? {
    "eks.amazonaws.com/role-arn" = aws_iam_role.kyverno_ecr[0].arn
  } : {}

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
    features = {
      logging = { verbosity = var.engine_log_verbosity }
    }
    admissionController = {
      replicas  = var.replica_count
      podLabels = local.k8s_labels
      # IRSA: lets the admission controller pull cosign signatures from ECR (the EKS pod-identity
      # webhook injects AWS_REGION/creds from this annotation). Empty when verification is off.
      # The chart nests the SA under rbac.serviceAccount.
      rbac = { serviceAccount = { annotations = local.irsa_sa_annotations } }
    }
    # Leader-elected controllers: a single active replica regardless of count.
    backgroundController = { replicas = 1 }
    reportsController = {
      replicas = 1
      rbac     = { serviceAccount = { annotations = local.irsa_sa_annotations } }
    }
    cleanupController = { replicas = 1 }
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
    enableImageVerification = var.enable_image_verification
    verifyFailureAction     = var.verify_failure_action
    verifyFailurePolicy     = local.verify_failure_policy
    verifySubjects          = var.verify_subjects
    rekorUrl                = var.rekor_url

    enableAttestationVerification = var.enable_attestation_verification
    attestFailureAction           = var.attest_failure_action
    attestFailurePolicy           = local.attest_failure_policy

    trustedCiSubjectRegExp = var.trusted_ci_subject_regexp
    attestCallerRepos      = var.attest_caller_repos
    enableHttprouteGuard   = var.enable_httproute_guard
    tenantHostnamePatterns = var.tenant_hostname_patterns
    enableCleanup          = var.enable_cleanup
    additionalPolicies     = var.additional_policies
    commonLabels           = local.k8s_labels
  }
}

# ---------------------------------------------------------------------------
# IRSA — Kyverno ECR read (for verifyImages signature fetch)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "kyverno_trust" {
  count = local.create_irsa ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Admission controller verifies at admission; reports controller for background image scans.
    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values = [
        "system:serviceaccount:${var.namespace}:kyverno-admission-controller",
        "system:serviceaccount:${var.namespace}:kyverno-reports-controller",
      ]
    }
  }
}

resource "aws_iam_role" "kyverno_ecr" {
  count = local.create_irsa ? 1 : 0

  name_prefix        = "kyverno-ecr-"
  assume_role_policy = data.aws_iam_policy_document.kyverno_trust[0].json

  tags = var.tags
}

data "aws_iam_policy_document" "kyverno_ecr" {
  count = local.create_irsa ? 1 : 0

  statement {
    sid       = "EcrAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "EcrReadTeamRepos"
    effect = "Allow"
    actions = [
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchCheckLayerAvailability",
    ]
    # Read-only, scoped to the team-* repos. Cross-account read from preprod is additionally allowed
    # by the ECR repo policy (pull_account_ids), as the node role does today.
    resources = ["arn:aws:ecr:${var.ecr_region}:${var.ecr_account_id}:repository/team-*"]
  }
}

resource "aws_iam_role_policy" "kyverno_ecr" {
  count = local.create_irsa ? 1 : 0

  name   = "ecr-read"
  role   = aws_iam_role.kyverno_ecr[0].id
  policy = data.aws_iam_policy_document.kyverno_ecr[0].json
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
