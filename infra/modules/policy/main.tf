locals {
  create = var.create

  # Audit rollout keeps the webhook fail-open (Ignore) so a policy/engine problem can never block
  # admission; only once Enforce + HA are proven do we fail-closed (Fail).
  failure_policy        = var.validation_failure_action == "Enforce" ? "Fail" : "Ignore"
  verify_failure_policy = var.verify_failure_action == "Enforce" ? "Fail" : "Ignore"
  attest_failure_policy = var.attest_failure_action == "Enforce" ? "Fail" : "Ignore"

  # Webhook server ports on hostNetwork — each hostNetwork webhook pod claims a NODE port, so they must be
  # distinct to co-exist on a node. 9443 is ALSO claimed by Crossplane's provider-kubernetes, whose Object-CRD
  # conversion webhook binds controller-runtime's hardcoded :9443 (unconfigurable in provider-kubernetes
  # v1.2.1) on hostNetwork — so the admission controller (previously 9443) collided with it whenever they
  # co-scheduled, crash-looping the provider. Move admission off 9443 (the only side we can configure): admission
  # 9445, cleanup 9444. Probes must follow (the chart defaults them to 9443); autoUpdateWebhooks re-registers.
  admission_server_port = var.webhook_host_network ? 9445 : 9443
  cleanup_server_port   = var.webhook_host_network ? 9444 : 9443

  # Kyverno needs ECR read (IRSA) to fetch cosign signatures for verifyImages (Phase 3).
  create_image_role            = local.create && var.enable_image_verification # Kyverno ECR read (Pod Identity)
  kyverno_ecr_service_accounts = toset(["kyverno-admission-controller", "kyverno-reports-controller"])

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
      # restarted on an informer-sync timeout and could no longer rebind :8080, blocking all environment
      # admission). Disabling it on hostNetwork removes the failure mode; relocating the port would just
      # move the lingering-socket problem. "0" disables (chart default ":8080").
      controllerRuntimeMetrics = { bindAddress = var.webhook_host_network ? "0" : ":8080" }
    }
    admissionController = merge({
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
      rbac = { serviceAccount = { annotations = {} } } # SA bound to the ECR role via Pod Identity (ADR-047)
      # Webhook server port off 9443 on hostNetwork (see local.admission_server_port) so it never collides
      # with provider-kubernetes' hardcoded :9443. The service's targetPort follows webhookServer.port, and
      # autoUpdateWebhooks repoints the webhook configs — so the API-server path (kyverno-svc:443) is unchanged.
      webhookServer = { port = local.admission_server_port }
      }, var.webhook_host_network ? {
      # The probes' httpGet port must follow the server (chart defaults them to 9443). Full blocks (all keys on
      # every probe so the conditional branch is a single consistent type) = the chart's admission defaults with
      # only the port changed; partial overrides risk losing a default field.
      startupProbe = {
        httpGet             = { path = "/health/liveness", port = local.admission_server_port, scheme = "HTTPS" }
        failureThreshold    = 20
        initialDelaySeconds = 2
        periodSeconds       = 6
        successThreshold    = 1
        timeoutSeconds      = 1
      }
      livenessProbe = {
        httpGet             = { path = "/health/liveness", port = local.admission_server_port, scheme = "HTTPS" }
        failureThreshold    = 2
        initialDelaySeconds = 15
        periodSeconds       = 30
        successThreshold    = 1
        timeoutSeconds      = 5
      }
      readinessProbe = {
        httpGet             = { path = "/health/readiness", port = local.admission_server_port, scheme = "HTTPS" }
        failureThreshold    = 6
        initialDelaySeconds = 5
        periodSeconds       = 10
        successThreshold    = 1
        timeoutSeconds      = 5
      }
    } : {})
    # Leader-elected controllers: a single active replica regardless of count.
    backgroundController = { replicas = 1 }
    reportsController = {
      replicas = 1
      rbac     = { serviceAccount = { annotations = {} } } # SA bound to the ECR role via Pod Identity (ADR-047)
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
    validationFailureAction   = var.validation_failure_action
    failurePolicy             = local.failure_policy
    complianceTier            = var.compliance_tier
    allowedRegistries         = var.allowed_registries
    excludeNamespaces         = concat(var.exclude_namespaces, var.extra_exclude_namespaces)
    excludePrincipals         = concat(var.exclude_principals, var.extra_exclude_principals)
    environmentNamespaceLabel = var.environment_namespace_label
    requiredWorkloadLabels    = var.required_workload_labels
    enableMutateDefaults      = var.enable_mutate_defaults
    enablePdbGenerate         = var.enable_pdb_generate
    enableTopologySpread      = var.enable_topology_spread
    enableReplicaFloor        = var.enable_replica_floor
    replicaFloorFailureAction = var.replica_floor_failure_action
    enableImageVerification   = var.enable_image_verification
    verifyFailureAction       = var.verify_failure_action
    verifyFailurePolicy       = local.verify_failure_policy
    # v3 (ADR-067/069 §6): per-PRODUCT cosign verification. The v2 per-team verifySubjects / tenantRegistryMap /
    # migratedTeams / attestCallerRepos / sharedSignerCallerRepos / tenantHostnamePatterns / enableHttprouteGuard
    # were removed at the cutover (restrict-images / restrict-route-hostnames are Composition-owned per-Environment).
    verifySubjectsProduct = var.verify_subjects_product
    rekorUrl              = var.rekor_url

    enableAttestationVerification = var.enable_attestation_verification
    attestFailureAction           = var.attest_failure_action
    attestFailurePolicy           = local.attest_failure_policy

    trustedCiSubjectRegExp      = var.trusted_ci_subject_regexp
    trustedCiBuildSubjectRegExp = var.trusted_ci_build_subject_regexp
    enableCleanup               = var.enable_cleanup
    additionalPolicies          = var.additional_policies
    commonLabels                = local.k8s_labels
  }
}

# ---------------------------------------------------------------------------
# Kyverno ECR read (verifyImages signature fetch); AWS identity via EKS Pod Identity (ADR-047)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "kyverno_trust" {
  count = local.create_image_role ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "kyverno_ecr" {
  count = local.create_image_role ? 1 : 0

  name_prefix        = "kyverno-ecr-"
  assume_role_policy = data.aws_iam_policy_document.kyverno_trust[0].json

  tags = var.tags
}

data "aws_iam_policy_document" "kyverno_ecr" {
  count = local.create_image_role ? 1 : 0

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
  count = local.create_image_role ? 1 : 0

  name   = "ecr-read"
  role   = aws_iam_role.kyverno_ecr[0].id
  policy = data.aws_iam_policy_document.kyverno_ecr[0].json
}

# One association per Kyverno controller SA (admission + reports) -> the shared ECR-read role.
resource "aws_eks_pod_identity_association" "kyverno_ecr" {
  for_each = local.create_image_role ? local.kyverno_ecr_service_accounts : toset([])

  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = each.value
  role_arn        = aws_iam_role.kyverno_ecr[0].arn
  tags            = var.tags
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

locals {
  # Inert checksum over every policies-chart file — its change forces a helm upgrade when any ClusterPolicy
  # template changes. helm_release tracks VALUES, not chart-dir content, so without this an edit to a policy
  # template (e.g. an exclude rule) renders identically in terraform and never re-applies. Mirrors the crossplane
  # module's chart_checksum.
  policies_chart_checksum = sha256(join(",", [for f in sort(tolist(fileset("${path.module}/policies-chart", "**"))) : filesha256("${path.module}/policies-chart/${f}")]))
}

resource "helm_release" "policies" {
  count     = local.create ? 1 : 0
  name      = "kyverno-platform-policies"
  chart     = "${path.module}/policies-chart"
  namespace = var.namespace
  timeout   = var.helm_timeout
  wait      = var.helm_wait
  # NOT atomic: the ClusterPolicies are additive/idempotent, and during the initial bulk install Kyverno churns
  # its webhook config (more so while it spins resolving the not-yet-existing crossplane CRDs — XTenant/
  # ProviderConfig), so an individual policy create can hit a transient validate-policy webhook timeout. With
  # atomic+cleanup that single timeout rolls back ALL policies, so the install never accumulates progress and
  # can't converge on retry. Leaving partial state lets each retry create the remaining policies until complete.
  atomic          = false
  cleanup_on_fail = false

  values = [
    yamlencode(local.policies_values),
    yamlencode({ chartChecksum = local.policies_chart_checksum }),
  ]

  depends_on = [helm_release.kyverno]
}
