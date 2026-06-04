locals {
  create = var.create

  # Audit rollout keeps the webhook fail-open (Ignore) so a policy/engine problem can never block
  # admission; only once Enforce + HA are proven do we fail-closed (Fail).
  failure_policy        = var.validation_failure_action == "Enforce" ? "Fail" : "Ignore"
  verify_failure_policy = var.verify_failure_action == "Enforce" ? "Fail" : "Ignore"
  attest_failure_policy = var.attest_failure_action == "Enforce" ? "Fail" : "Ignore"

  # Cleanup controller webhook server port — moved off 9443 on hostNetwork to avoid colliding with the
  # admission controllers (which also bind 9443 on the host). Its health probes must follow it.
  cleanup_server_port = var.webhook_host_network ? 9444 : 9443

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
      # On hostNetwork the controller-runtime manager metrics server (:8080) becomes a HOST port. It is
      # redundant with Kyverno's own Prometheus metrics (the metering port, 8000/8001) and, on a rapid
      # restart, the host :8080 socket lingers so the next start fails "bind: address already in use" →
      # the admission controller CrashLoopBackOffs (observed after a node-churn/scale-up, when its manager
      # restarted on an informer-sync timeout and could no longer rebind :8080, blocking all tenant
      # admission). Disabling it on hostNetwork removes the failure mode; relocating the port would just
      # move the lingering-socket problem. "0" disables (chart default ":8080").
      controllerRuntimeMetrics = { bindAddress = var.webhook_host_network ? "0" : ":8080" }
    }
    admissionController = {
      replicas  = var.replica_count
      podLabels = local.k8s_labels
      # EKS + Cilium overlay (cluster-pool): the EKS managed control plane reaches admission
      # webhooks only at VPC-routable addresses, but overlay pod IPs (the pod CIDR) are not
      # routable from it. Run the webhook server on hostNetwork so the kyverno-svc endpoint is the
      # node's VPC IP the API server can dial; ClusterFirstWithHostNet keeps cluster DNS working.
      hostNetwork = var.webhook_host_network
      dnsPolicy   = var.webhook_host_network ? "ClusterFirstWithHostNet" : "ClusterFirst"
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
    # The cleanup controller also serves an API-server-called webhook → same hostNetwork need.
    # On hostNetwork its server (9443) + metrics (8000) become host ports that collide with the
    # admission controllers'. Move them to 9444/8001 so a 3rd admission HA replica can co-locate on
    # the cleanup controller's node (otherwise admission_replicas + 1 cleanup > nodes leaves one Pending).
    # The chart does NOT derive the probe ports from server.port (they default to 9443), so when the
    # server moves to 9444 the probes still hit 9443 — which only "works" if an admission pod (9443) is
    # co-located on the same node; on a single-replica cluster the cleanup pod can land on a node with
    # nothing on 9443 → probe fails → rollout stalls. Pin the probes to the cleanup server port too.
    cleanupController = merge({
      replicas    = 1
      hostNetwork = var.webhook_host_network
      dnsPolicy   = var.webhook_host_network ? "ClusterFirstWithHostNet" : "ClusterFirst"
      server      = { port = local.cleanup_server_port }
      metering    = { port = var.webhook_host_network ? 8001 : 8000 }
      }, var.webhook_host_network ? {
      startupProbe = {
        httpGet             = { path = "/health/liveness", port = local.cleanup_server_port, scheme = "HTTPS" }
        failureThreshold    = 20
        initialDelaySeconds = 2
        periodSeconds       = 6
        successThreshold    = 1
        timeoutSeconds      = 1
      }
      livenessProbe = {
        httpGet             = { path = "/health/liveness", port = local.cleanup_server_port, scheme = "HTTPS" }
        failureThreshold    = 2
        initialDelaySeconds = 15
        periodSeconds       = 30
        successThreshold    = 1
        timeoutSeconds      = 5
      }
      readinessProbe = {
        httpGet             = { path = "/health/readiness", port = local.cleanup_server_port, scheme = "HTTPS" }
        failureThreshold    = 6
        initialDelaySeconds = 5
        periodSeconds       = 10
        successThreshold    = 1
        timeoutSeconds      = 5
      }
    } : {})
  }

  # Policies (local chart) values — all dynamic, environment-specific knobs live here so the module
  # carries no team-specific data.
  policies_values = {
    validationFailureAction = var.validation_failure_action
    failurePolicy           = local.failure_policy
    complianceTier          = var.compliance_tier
    allowedRegistries       = var.allowed_registries
    tenantRegistryMap       = var.tenant_registry_map
    # Teams whose tenant infra (incl. the per-team restrict-* policies) is owned by the Crossplane Tenant
    # Composition (BACK stack P3). The chart skips restrict-images/restrict-route-hostnames for these to
    # avoid colliding with the Composition's; the platform-owned verify-images/attestations still apply.
    migratedTeams           = var.migrated_teams
    excludeNamespaces       = concat(var.exclude_namespaces, var.extra_exclude_namespaces)
    excludePrincipals       = concat(var.exclude_principals, var.extra_exclude_principals)
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
    # Shared build-sign reusable workflow (asanexample/trusted-ci/build-sign.yml): for teams in
    # sharedSignerCallerRepos the image signature + SBOM may also be signed by this shared workflow
    # (subject) gated by the githubWorkflowRepository extension (= the team's app repo), in addition
    # to the team's own app-workflow identity. Mirrors the provenance attestCallerRepos pattern.
    trustedCiBuildSubjectRegExp = var.trusted_ci_build_subject_regexp
    sharedSignerCallerRepos     = var.shared_signer_caller_repos
    enableHttprouteGuard        = var.enable_httproute_guard
    tenantHostnamePatterns      = var.tenant_hostname_patterns
    enableCleanup               = var.enable_cleanup
    additionalPolicies          = var.additional_policies
    commonLabels                = local.k8s_labels
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
