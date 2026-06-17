locals {
  create = var.create

  # Environment ECR repositories the provisioning role may manage: "repository/team-*" in the platform account.
  ecr_repo_arn = "arn:aws:ecr:${var.region}:${var.account_id}:repository/${var.environment_repo_prefix}*"

  enable_aws                      = local.create && length(var.provider_services) > 0
  enable_environment_provisioning = local.create && var.enable_environment_provisioning

  # The per-app Pod-* workload IAM roles (v2: Pod-<team>-<name>-<env>-<app>) the provisioning role may
  # create/manage (in this workload account). PassRole is scoped to these only (the roles handed to EKS
  # Pod Identity).
  environment_role_arn_pattern = "arn:aws:iam::${var.account_id}:role/${var.environment_role_name_prefix}*"

  # Roles the provisioning role may create/manage: the Pod-* workload roles AND the DeveloperAccess-*
  # per-team developer-access roles (P2c). Both name prefixes, same account.
  manageable_role_arn_patterns = [
    local.environment_role_arn_pattern,
    "arn:aws:iam::${var.account_id}:role/${var.developer_role_name_prefix}*",
  ]

  # AWS family providers share one SA (so a single Pod Identity association credentials them) and serve on
  # hostNetwork (their CRDs are multi-version → the EKS control plane must reach the conversion webhook).
  # The family provider is installed EXPLICITLY (first) and every member sets skipDependencyResolution, so
  # the members don't contend on the Lock resolving the shared family dependency (only one wins otherwise —
  # crossplane-contrib/provider-aws#1749). The family has single-version CRDs → no hostNetwork.
  aws_providers = local.enable_aws ? concat(
    [{
      name                     = "provider-family-aws"
      package                  = "${var.provider_registry}/provider-family-aws:${var.provider_version}"
      serviceAccount           = var.provider_service_account
      hostNetwork              = false
      skipDependencyResolution = true
      avoidKyvernoWebhookNode  = false
    }],
    [for svc in var.provider_services : {
      name                     = "provider-aws-${svc}"
      package                  = "${var.provider_registry}/provider-aws-${svc}:${var.provider_version}"
      serviceAccount           = var.provider_service_account
      hostNetwork              = true
      skipDependencyResolution = true
      avoidKyvernoWebhookNode  = false
    }]
  ) : []

  # provider-kubernetes runs in-cluster (InjectedIdentity); its own SA carries a scoped ClusterRole. It has
  # no package dependencies; skipDependencyResolution avoids any Lock contention with the aws providers.
  k8s_provider = var.enable_kubernetes_provider ? [{
    name                     = "provider-kubernetes"
    package                  = var.kubernetes_provider_package
    serviceAccount           = "provider-kubernetes"
    hostNetwork              = var.kubernetes_provider_hostnetwork
    skipDependencyResolution = true
    # Conversion webhook binds controller-runtime's default :9443 (WEBHOOK_PORT doesn't move it); under
    # hostNetwork that collides with Kyverno's admission controller on its node. Anti-affinity keeps them apart.
    avoidKyvernoWebhookNode = var.kubernetes_provider_hostnetwork
  }] : []

  # k8s_provider FIRST so provider-kubernetes keeps list index 0 (and thus its port assignment) stable across
  # phases — adding the aws providers must not re-index it (an index change rewrites its DRC ports, forcing a
  # disruptive restart that can reschedule it onto a node where its fixed ports collide). New providers append.
  providers = concat(local.k8s_provider, local.aws_providers)

  # ProviderConfig CRDs the wait-Job gates on (each installed asynchronously by its provider package).
  wait_for_crds = concat(
    local.enable_aws ? ["providerconfigs.aws.upbound.io"] : [],
    var.enable_kubernetes_provider ? ["providerconfigs.kubernetes.crossplane.io"] : [],
  )

  # Content checksum per LOCAL chart, carried as a release value so the helm provider re-renders when any chart
  # file changes. A template/raw-file-only change (e.g. the Composition in files/, a CRD template, the provider
  # RBAC) does NOT alter the release's other values, so the provider would otherwise skip the upgrade — the
  # gotcha that silently dropped the config-chart RBAC and the env_api Composition until a value happened to
  # change. Hash every file in the chart dir; the value is inert (charts don't read it) but its change forces
  # the in-place upgrade.
  chart_checksum = {
    for c in ["runtime", "config", "environment-api"] :
    c => sha256(join(",", [for f in sort(tolist(fileset("${path.module}/charts/${c}", "**"))) : filesha256("${path.module}/charts/${c}/${f}")]))
  }
}

# ---------------------------------------------------------------------------
# Crossplane core (control plane)
# ---------------------------------------------------------------------------
# Installed as a Terragrunt-managed Helm add-on, like every other platform service (Kyverno, cert-manager,
# Cilium). Crossplane is the *environment* control plane (ADR-046); foundational/platform infra stays on
# Terragrunt. The core chart installs the pkg.crossplane.io CRDs (Provider, DeploymentRuntimeConfig) and the
# package + rbac managers.

resource "helm_release" "crossplane" {
  count = local.create ? 1 : 0

  name             = "crossplane"
  repository       = var.helm_repository
  chart            = "crossplane"
  version          = var.helm_chart_version
  namespace        = var.namespace
  create_namespace = true
  timeout          = var.helm_timeout
  wait             = var.helm_wait
  atomic           = var.helm_wait
  cleanup_on_fail  = true
}

# ---------------------------------------------------------------------------
# Provider runtime (local chart): DeploymentRuntimeConfig + Provider CRs + a wait-Job
# ---------------------------------------------------------------------------
# Delivered as a local Helm chart rather than kubernetes_manifest: the Provider / DeploymentRuntimeConfig
# CRs reference CRDs the core release installs in the SAME apply, which kubernetes_manifest cannot plan
# against (CRD-not-found at plan time). A local chart needs no plan-time CRD access; depends_on guarantees
# the core CRDs exist first. Same pattern as the policy module's policies-chart.
#
# The chart's post-install Job blocks (helm wait=true) until the providers report Healthy — which is when
# the provider package finishes installing the aws.upbound.io ProviderConfig CRD. That gate is what lets
# the separate ProviderConfig release (below) apply cleanly.

resource "helm_release" "crossplane_runtime" {
  count = local.create ? 1 : 0

  name      = "crossplane-runtime"
  chart     = "${path.module}/charts/runtime"
  namespace = var.namespace
  timeout   = var.helm_timeout
  wait      = var.helm_wait
  atomic    = var.helm_wait

  values = [yamlencode({
    namespace     = var.namespace
    waitImage     = var.wait_image
    providers     = local.providers
    functions     = var.functions
    waitForCrds   = local.wait_for_crds
    chartChecksum = local.chart_checksum["runtime"]
  })]

  depends_on = [helm_release.crossplane]
}

# ProviderConfig — separate release so it applies only after the runtime release's wait-Job has confirmed
# the providers are Healthy (and thus the aws.upbound.io ProviderConfig CRD exists). Credentials come from
# EKS Pod Identity (ADR-041): no SA annotation, no OIDC — the association below is the only credential grant.

resource "helm_release" "crossplane_config" {
  count = local.create ? 1 : 0

  name      = "crossplane-config"
  chart     = "${path.module}/charts/config"
  namespace = var.namespace
  timeout   = var.helm_timeout
  # NOT wait/atomic on this release: it owns the provider ProviderConfigs, which destroy BEFORE the providers
  # (crossplane_runtime) — so at uninstall time the provider controller is still running and re-adds the
  # ProviderConfig's `in-use.crossplane.io` finalizer faster than the teardown cleanup clears it. With wait=true
  # the helm uninstall then blocks ~10m on the ProviderConfig deletion and fails ("context deadline exceeded" —
  # the platform/preprod crossplane teardown failure). wait=false lets helm issue the delete and return; the
  # finalizer-cleared ProviderConfig is reaped when the provider/CRD are torn down. Install needs no wait either:
  # ProviderConfigs/RBAC are plain config objects with no readiness gate.
  wait   = false
  atomic = false

  values = [yamlencode({
    namespace             = var.namespace
    providerConfigName    = var.providerconfig_name
    enableAws             = local.enable_aws
    enableKubernetes      = var.enable_kubernetes_provider
    ecrProvisionerRoleArn = var.ecr_provisioner_role_arn # platform-ecr ProviderConfig (assumeRoleChain)
    chartChecksum         = local.chart_checksum["config"]
  })]

  depends_on = [helm_release.crossplane_runtime]
}

# ---------------------------------------------------------------------------
# Environment API (local chart): the Environment XRD + Composition + the shared environment-developer ClusterRole
# ---------------------------------------------------------------------------
# Workload clusters only (ADR-048). The Composition (function-go-templating) renders a environment's Kubernetes
# resources via provider-kubernetes. Applied after config so the kubernetes ProviderConfig + the function
# exist. Crossplane core validates XRD/Composition at admission — see the README note on the overlay webhook.

resource "helm_release" "crossplane_environment_api" {
  count = local.create && var.enable_environment_api ? 1 : 0

  name      = "crossplane-environment-api"
  chart     = "${path.module}/charts/environment-api"
  namespace = var.namespace
  timeout   = var.helm_timeout
  wait      = var.helm_wait
  atomic    = var.helm_wait

  values = [yamlencode({
    providerConfigName = var.providerconfig_name
    chartChecksum      = local.chart_checksum["environment-api"]
    # The shared environment-developer ClusterRole the Composition's per-environment RoleBindings reference. The retired v1
    # `environment` module used to own it (coexistence → default false); on a fresh v2 build the environment chart creates it.
    createDeveloperClusterRole = var.create_developer_cluster_role
    # Cluster constants for the Composition, injected via an EnvironmentConfig (the claim API stays clean).
    environment = {
      ecrRegistry             = var.ecr_registry
      baseDomain              = var.base_domain
      region                  = var.region
      workloadAccountId       = var.account_id
      managementAccountId     = var.management_account_id
      clusterName             = var.cluster_name
      pullAccountIds          = var.environment_pull_account_ids
      resourcePrefix          = var.environment_resource_prefix
      permissionsBoundaryArn  = local.enable_environment_provisioning ? aws_iam_policy.environment_boundary[0].arn : ""
      providerConfigEcr       = var.ecr_provisioner_role_arn != "" ? "platform-ecr" : var.providerconfig_name
      podIdentityServiceAccnt = var.provider_service_account
    }
  })]

  depends_on = [helm_release.crossplane_config]
}

# ---------------------------------------------------------------------------
# Environment control-plane Kyverno policies (local chart)
# ---------------------------------------------------------------------------
# restrict-environment-envelope (ADR-067 #387) + restrict-environment-control-plane (ADR-046/048). They match
# Crossplane CRDs — XEnvironment, the projected Team/Product, and the provider ProviderConfigs — so they live
# with the environment control plane, NOT in the policy unit. The policy unit deploys BEFORE crossplane (it must, to
# pre-create the crossplane-system Kyverno exclusion), so if these two policies shipped there Kyverno would churn
# its webhook config resolving the not-yet-existing XEnvironment/ProviderConfig kinds — which is exactly what
# stalled the preprod `policy` install (a single transient validate-policy webhook timeout rolling the whole
# bundle back). Installed here, AFTER crossplane_environment_api (which creates the XEnvironment + Team/Product CRDs),
# every kind they match already exists, so admission registration is clean. (Teams are now git-native —
# gitops/teams, synced by argocd-apps — so the v2 crossplane-teams Helm projection was removed at the cutover.)
#
# Gated on enable_environment_api (workload clusters): where there's no environment control plane there's no XEnvironment
# CRD and ProviderConfigs are platform-managed only, so neither policy has anything to guard.
resource "helm_release" "crossplane_environment_policies" {
  count = local.create && var.enable_environment_api ? 1 : 0

  name      = "crossplane-environment-policies"
  chart     = "${path.module}/charts/environment-policies"
  namespace = var.namespace
  timeout   = var.helm_timeout
  wait      = var.helm_wait
  # NOT atomic: ClusterPolicies are additive/idempotent and Kyverno can still briefly churn its webhook config
  # during a bulk install, so one transient validate-policy webhook timeout shouldn't roll back both policies
  # (same reasoning as the policy module's policies-chart release). Leaving partial state lets a retry converge.
  atomic          = false
  cleanup_on_fail = false

  # Defaults (chart values.yaml) reproduce what the policy unit passed for these two policies pre-move:
  # control-plane Enforce, envelope Audit-first, failurePolicy Fail, crossplane-system in the skip list. The
  # unit can override (e.g. enableEnvironmentEnvelope=true at the cutover) via var.environment_policy_values.
  values = [yamlencode(var.environment_policy_values)]

  depends_on = [helm_release.crossplane_environment_api]
}

# ---------------------------------------------------------------------------
# Teardown: drain Crossplane CR finalizers before the helm uninstalls
# ---------------------------------------------------------------------------
# Provider/ProviderRevision/Function/XRD/Composition/ProviderConfig/Usage CRs carry finalizers the package +
# apiextensions managers drain asynchronously (uninstalling provider packages, deleting generated CRDs). That
# drain runs longer than the helm uninstall timeout → "Error uninstalling release ... context deadline exceeded"
# (the observed preprod/crossplane teardown failure). This runs FIRST on teardown (depends_on every release =>
# reverse-order destroy) and DELETEs + force-clears those CRs (--delete): deletion sets deletionTimestamp, the
# finalizer strip then forces removal regardless of the controller. The cluster is being torn down, so orphaned
# in-cluster packages don't matter — the goal is letting the helm uninstalls find the CRs already drained.
# Best-effort + self-authenticating (scripts/k8s-finalizer-clear.sh); a missing CRD is a no-op.
resource "null_resource" "crd_finalizer_cleanup" {
  count = local.create ? 1 : 0

  triggers = {
    script   = var.finalizer_clear_script
    cluster  = var.cluster_name
    region   = var.region
    role_arn = var.deployer_role_arn
    # Two classes of CR, handled differently to avoid racing the helm uninstalls that follow:
    #
    # HELM-OWNED (these CRs are rendered by the crossplane charts, so the helm uninstall is the deleter):
    # CLEAR FINALIZERS ONLY — do NOT --delete them. Pre-clearing the finalizer means the later helm uninstall
    # deletes them instantly instead of hanging on the (concurrently-removed) controller's finalizer drain. If
    # we ALSO --delete here we delete the object out from under helm, and the uninstall then fails with
    # "failed to delete release" (the observed platform/crossplane teardown failure on the config chart's
    # ProviderConfigs). XRD/Composition/EnvironmentConfig (environment chart), Provider/Function/Configuration +
    # DeploymentRuntimeConfig (runtime chart), and both ProviderConfigs (config chart).
    refs_helm_owned = join(" ", [
      "compositeresourcedefinitions.apiextensions.crossplane.io",
      "compositions.apiextensions.crossplane.io",
      "environmentconfigs.apiextensions.crossplane.io",
      "providers.pkg.crossplane.io",
      "functions.pkg.crossplane.io",
      "configurations.pkg.crossplane.io",
      "deploymentruntimeconfigs.pkg.crossplane.io",
      "providerconfigs.aws.upbound.io",
      "providerconfigs.kubernetes.crossplane.io",
    ])
    # ORPHANS (controller-generated at runtime, in NO chart, so nothing else deletes them): --delete them,
    # else they linger with finalizers and block their CRD's removal.
    #
    # ProviderConfigUsage is FIRST and load-bearing: each managed resource creates one, and while ANY usage
    # references a ProviderConfig, crossplane core keeps the `in-use.crossplane.io` finalizer on that
    # ProviderConfig — and RE-ADDS it if we only clear it. So clearing the ProviderConfig finalizer alone is
    # futile (the config chart's helm uninstall then hangs ~10m waiting for a delete that core keeps blocking,
    # -> "context deadline exceeded"). Deleting the usages makes core release the in-use finalizer, so the
    # ProviderConfig (cleared in pass 1) actually deletes and the uninstall completes. Then the apiextensions
    # Usage + the package revisions (Provider/FunctionRevision).
    refs_orphan = join(" ", [
      "providerconfigusages.aws.upbound.io",
      "providerconfigusages.kubernetes.crossplane.io",
      "usages.apiextensions.crossplane.io",
      "providerrevisions.pkg.crossplane.io",
      "functionrevisions.pkg.crossplane.io",
    ])
  }

  # Pass 1 — helm-owned CRs: clear finalizers only (helm uninstall deletes the objects).
  provisioner "local-exec" {
    when    = destroy
    command = "bash ${self.triggers.script} ${self.triggers.cluster} ${self.triggers.region} ${self.triggers.role_arn} - ${self.triggers.refs_helm_owned}"
  }

  # Pass 2 — orphan CRs: delete + clear finalizers (nothing else removes them).
  provisioner "local-exec" {
    when    = destroy
    command = "bash ${self.triggers.script} --delete ${self.triggers.cluster} ${self.triggers.region} ${self.triggers.role_arn} - ${self.triggers.refs_orphan}"
  }

  depends_on = [
    helm_release.crossplane,
    helm_release.crossplane_runtime,
    helm_release.crossplane_config,
    helm_release.crossplane_environment_api,
    helm_release.crossplane_environment_policies,
  ]
}

# ---------------------------------------------------------------------------
# Teardown: sweep orphaned Crossplane-provisioned environment IAM roles (AWS-side)
# ---------------------------------------------------------------------------
# crd_finalizer_cleanup (above) drains the IN-CLUSTER Crossplane CRs so the helm uninstalls succeed — but
# uninstalling Crossplane never deletes the EXTERNAL AWS resources its Composition created. The per-environment
# Pod-<...> workload roles and the DeveloperAccess-<team> roles persist with this deny-escalation boundary
# attached as their PermissionsBoundary, so aws_iam_policy.environment_boundary then fails to delete ("DeleteConflict:
# Cannot delete a policy attached to entities"), failing the whole unit teardown (observed on preprod). This
# sweep deletes exactly those roles (only ones carrying this boundary — by the S2 condition the provisioner can
# create roles ONLY with it, so every match is a environment role). It depends_on the boundary, so its when=destroy
# provisioner runs BEFORE the boundary is deleted (reverse-order destroy). The script always exits 0 — best-effort,
# never blocks destroy. Reuses the scripts/ dir of finalizer_clear_script so no extra unit wiring is needed.
resource "null_resource" "environment_iam_orphan_sweep" {
  count = local.enable_environment_provisioning ? 1 : 0

  triggers = {
    script       = "${dirname(var.finalizer_clear_script)}/environment-iam-orphan-sweep.sh"
    boundary_arn = aws_iam_policy.environment_boundary[0].arn
    region       = var.region
    role_arn     = var.deployer_role_arn
  }

  provisioner "local-exec" {
    when    = destroy
    command = "bash ${self.triggers.script} ${self.triggers.boundary_arn} ${self.triggers.region} ${self.triggers.role_arn}"
  }
}

# Sibling of the IAM sweep for the cross-account environment ECR repos (team-<team>/<app>) the Composition created
# in the platform account. Uninstalling Crossplane orphans them too; they don't block teardown (a rebuild
# re-adopts them by external-name), but a clean teardown removes them so each cycle starts pristine. Gated on a
# sweep role being provided (the platform PlatformDeployer — the in-account ecr-provisioner role is NOT
# assumable by the teardown profile, only via the provider's assumeRoleChain). Best-effort; never blocks destroy.
resource "null_resource" "environment_ecr_orphan_sweep" {
  count = local.enable_environment_provisioning && var.ecr_orphan_sweep_role_arn != "" ? 1 : 0

  triggers = {
    script   = "${dirname(var.finalizer_clear_script)}/environment-ecr-orphan-sweep.sh"
    role_arn = var.ecr_orphan_sweep_role_arn
    region   = var.region
  }

  provisioner "local-exec" {
    when    = destroy
    command = "bash ${self.triggers.script} ${self.triggers.role_arn} ${self.triggers.region}"
  }
}

# ---------------------------------------------------------------------------
# Scoped provisioning identity (IAM) + EKS Pod Identity association
# ---------------------------------------------------------------------------
# The AWS provider assumes this role to provision environment resources. P1 scope: ECR repositories under
# "team-*" only (the demo + the eventual per-team ECR repos). Later phases EXTEND this policy (IAM roles +
# Pod Identity associations for the Environment Composition) — at which point a permissions boundary on
# created roles and the org SCP exempt_roles entry (DenyTeamTagTampering) become required. Treat this
# identity like the deployer role: broadly capable within its scope and a high-value target (ADR-046).

data "aws_iam_policy_document" "assume" {
  count = local.enable_aws ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "provisioner" {
  count = local.enable_aws ? 1 : 0

  name               = "crossplane-provisioner-${var.cluster_name}"
  description        = "Crossplane AWS provider - environment resource provisioning (ECR). EKS Pod Identity (ADR-046)."
  assume_role_policy = data.aws_iam_policy_document.assume[0].json
  tags               = var.tags
}

# ---------------------------------------------------------------------------
# Deny-escalation permissions boundary (P2b) — the cap on every Crossplane-created Pod-team role.
# ---------------------------------------------------------------------------
# Effective environment-role perms = (the role's declared policy) ∩ (this boundary). Even if the provisioning
# identity is tricked into attaching admin, the boundary keeps a environment role from privilege escalation.
data "aws_iam_policy_document" "environment_boundary" {
  count = local.enable_environment_provisioning ? 1 : 0

  statement {
    sid       = "AllowAll"
    effect    = "Allow"
    actions   = ["*"]
    resources = ["*"]
  }
  statement {
    sid    = "DenyEscalation"
    effect = "Deny"
    actions = [
      "iam:*",
      "organizations:*",
      "account:*",
      "sts:AssumeRole",
      "sts:AssumeRoleWithSAML",
      "sts:AssumeRoleWithWebIdentity",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "environment_boundary" {
  count = local.enable_environment_provisioning ? 1 : 0

  name        = "environment-permissions-boundary-${var.cluster_name}"
  description = "Deny-escalation boundary attached to every Crossplane-provisioned Pod-team-* role (S2)."
  policy      = data.aws_iam_policy_document.environment_boundary[0].json
  tags        = var.tags
}

data "aws_iam_policy_document" "provisioner" {
  count = local.enable_aws ? 1 : 0

  # Platform hub (P1): ECR repositories provisioned LOCALLY. Not used on a environment-provisioning workload
  # cluster (preprod), where ECR is cross-account (via the assumed platform role below).
  dynamic "statement" {
    for_each = local.enable_environment_provisioning ? [] : [1]
    content {
      sid    = "EnvironmentEcrRepositoriesLocal"
      effect = "Allow"
      actions = [
        "ecr:CreateRepository", "ecr:DeleteRepository", "ecr:DescribeRepositories",
        "ecr:ListTagsForResource", "ecr:TagResource", "ecr:UntagResource",
        "ecr:PutLifecyclePolicy", "ecr:GetLifecyclePolicy", "ecr:DeleteLifecyclePolicy",
        "ecr:PutImageScanningConfiguration", "ecr:PutImageTagMutability",
        "ecr:SetRepositoryPolicy", "ecr:GetRepositoryPolicy", "ecr:DeleteRepositoryPolicy",
      ]
      resources = [local.ecr_repo_arn]
    }
  }

  # Environment provisioning (workload cluster): create Pod-team-* roles ONLY with the boundary attached.
  dynamic "statement" {
    for_each = local.enable_environment_provisioning ? [1] : []
    content {
      sid       = "EnvironmentIamCreateRoleBoundedOnly"
      effect    = "Allow"
      actions   = ["iam:CreateRole"]
      resources = local.manageable_role_arn_patterns
      condition {
        test     = "StringEquals"
        variable = "iam:PermissionsBoundary"
        values   = [aws_iam_policy.environment_boundary[0].arn]
      }
    }
  }
  # Manage the created roles (NO Put/DeleteRolePermissionsBoundary → cannot strip the boundary).
  dynamic "statement" {
    for_each = local.enable_environment_provisioning ? [1] : []
    content {
      sid    = "EnvironmentIamManageRoles"
      effect = "Allow"
      actions = [
        "iam:DeleteRole", "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:GetRolePolicy",
        "iam:ListRolePolicies", "iam:TagRole", "iam:UntagRole", "iam:GetRole", "iam:ListRoleTags",
        # provider-upjet-aws observes a Role by also listing its *attached* (managed) policies, even though
        # we only ever attach inline policies — without this the observe 403s and the MR never goes Ready.
        "iam:ListAttachedRolePolicies",
        # On delete, the provider lists instance profiles for the role (to detach any) before DeleteRole.
        "iam:ListInstanceProfilesForRole",
      ]
      resources = local.manageable_role_arn_patterns
    }
  }
  # PassRole the environment roles to EKS Pod Identity only.
  dynamic "statement" {
    for_each = local.enable_environment_provisioning ? [1] : []
    content {
      sid       = "EnvironmentIamPassRole"
      effect    = "Allow"
      actions   = ["iam:PassRole"]
      resources = [local.environment_role_arn_pattern]
      condition {
        test     = "StringEquals"
        variable = "iam:PassedToService"
        values   = ["pods.eks.amazonaws.com"]
      }
    }
  }
  # EKS Pod Identity associations on this cluster.
  dynamic "statement" {
    for_each = local.enable_environment_provisioning ? [1] : []
    content {
      sid    = "EnvironmentPodIdentityAssociations"
      effect = "Allow"
      actions = [
        "eks:CreatePodIdentityAssociation", "eks:DeletePodIdentityAssociation",
        "eks:UpdatePodIdentityAssociation", "eks:DescribePodIdentityAssociation",
        "eks:ListPodIdentityAssociations",
        # The association carries a Team tag; CreatePodIdentityAssociation with tags needs eks:TagResource
        # (and UntagResource for drift correction / delete).
        "eks:TagResource", "eks:UntagResource",
      ]
      resources = [
        "arn:aws:eks:${var.region}:${var.account_id}:cluster/${var.cluster_name}",
        "arn:aws:eks:${var.region}:${var.account_id}:podidentityassociation/${var.cluster_name}/*",
      ]
    }
  }
  # EKS access entries on this cluster (P2c): map the per-team DeveloperAccess-<team> role to the
  # team-<team>:developers Kubernetes group. Authorized on the cluster + access-entry resources.
  dynamic "statement" {
    for_each = local.enable_environment_provisioning ? [1] : []
    content {
      sid    = "EnvironmentEksAccessEntries"
      effect = "Allow"
      actions = [
        "eks:CreateAccessEntry", "eks:DeleteAccessEntry", "eks:DescribeAccessEntry",
        "eks:UpdateAccessEntry", "eks:ListAccessEntries",
        # Group-mapped entries don't associate an AWS access policy, but upjet calls these on observe.
        "eks:AssociateAccessPolicy", "eks:DisassociateAccessPolicy", "eks:ListAssociatedAccessPolicies",
        # The entry carries a Team tag (create-with-tags needs eks:TagResource; Untag for drift/delete).
        "eks:TagResource", "eks:UntagResource",
      ]
      resources = [
        "arn:aws:eks:${var.region}:${var.account_id}:cluster/${var.cluster_name}",
        "arn:aws:eks:${var.region}:${var.account_id}:access-entry/${var.cluster_name}/*",
      ]
    }
  }
  # Assume the platform-account role to provision environment ECR repos cross-account.
  dynamic "statement" {
    for_each = local.enable_environment_provisioning && var.ecr_provisioner_role_arn != "" ? [1] : []
    content {
      sid    = "AssumePlatformEcrProvisioner"
      effect = "Allow"
      # provider-upjet-aws passes session tags on the assumeRoleChain hop, so the chain needs sts:TagSession
      # alongside sts:AssumeRole (the target role's trust policy must allow sts:TagSession too).
      actions   = ["sts:AssumeRole", "sts:TagSession"]
      resources = [var.ecr_provisioner_role_arn]
    }
  }

  # Self-service S3 buckets (ADR-073, the resource paved road). Bucket lifecycle + the safe-by-construction
  # config the Composition's MRs set. Scoped to `${var.environment_resource_prefix}*` bucket names (the
  # platform-controlled refplat-<team>-<product>-<stage>-<name> convention; cross-team isolation is enforced at
  # the WORKLOAD role, which gets per-bucket object access — this provisioner is shared platform infra) and
  # pinned to this cluster's region. Object-level access is intentionally NOT here (provisioning is config-only;
  # the workload role gets the per-bucket Get/Put/etc). Added only when the s3 provider is installed.
  dynamic "statement" {
    for_each = local.enable_environment_provisioning && contains(var.provider_services, "s3") ? [1] : []
    content {
      sid    = "EnvironmentS3Buckets"
      effect = "Allow"
      actions = [
        "s3:CreateBucket", "s3:DeleteBucket",
        "s3:PutBucketTagging", "s3:GetBucketTagging",
        "s3:PutBucketPublicAccessBlock", "s3:GetBucketPublicAccessBlock",
        "s3:PutEncryptionConfiguration", "s3:GetEncryptionConfiguration",
        "s3:PutBucketVersioning", "s3:GetBucketVersioning",
        "s3:PutBucketOwnershipControls", "s3:GetBucketOwnershipControls",
        "s3:PutBucketPolicy", "s3:GetBucketPolicy", "s3:DeleteBucketPolicy",
        # Observe-only reads provider-upjet-aws issues when reconciling a Bucket and its sub-resources.
        "s3:GetBucketAcl", "s3:GetBucketLocation", "s3:GetAccelerateConfiguration",
        "s3:GetBucketObjectLockConfiguration", "s3:GetBucketRequestPayment", "s3:GetBucketLogging",
        "s3:GetLifecycleConfiguration", "s3:GetReplicationConfiguration", "s3:GetBucketWebsite",
        "s3:GetBucketCORS", "s3:ListBucket",
      ]
      resources = ["arn:aws:s3:::${var.environment_resource_prefix}*"]
      condition {
        test     = "StringEquals"
        variable = "aws:RequestedRegion"
        values   = [var.region]
      }
    }
  }

  # Self-service SQS queues (ADR-073 Phase A.1). Queue lifecycle + the safe-config the Composition sets (SSE,
  # deny-non-TLS policy, tags). Scoped to `${var.environment_resource_prefix}*` queue names in this region/
  # account; the WORKLOAD role gets the per-queue send/receive. Added only when the sqs provider is installed.
  dynamic "statement" {
    for_each = local.enable_environment_provisioning && contains(var.provider_services, "sqs") ? [1] : []
    content {
      sid    = "EnvironmentSqsQueues"
      effect = "Allow"
      actions = [
        "sqs:CreateQueue", "sqs:DeleteQueue",
        "sqs:GetQueueAttributes", "sqs:SetQueueAttributes", "sqs:GetQueueUrl",
        "sqs:TagQueue", "sqs:UntagQueue", "sqs:ListQueueTags",
        # Manage the queue access policy (the deny-non-TLS statement).
        "sqs:AddPermission", "sqs:RemovePermission",
        # Observe: the provider lists a queue's DLQ source relationships on reconcile.
        "sqs:ListDeadLetterSourceQueues",
      ]
      resources = ["arn:aws:sqs:${var.region}:${var.account_id}:${var.environment_resource_prefix}*"]
      condition {
        test     = "StringEquals"
        variable = "aws:RequestedRegion"
        values   = [var.region]
      }
    }
  }
  # sqs:ListQueues has no resource-level scope (account-wide enumeration); the provider may call it on observe.
  # Read-only, pinned to this region. Separate statement so the CRUD actions above stay scoped to refplat-*.
  dynamic "statement" {
    for_each = local.enable_environment_provisioning && contains(var.provider_services, "sqs") ? [1] : []
    content {
      sid       = "EnvironmentSqsList"
      effect    = "Allow"
      actions   = ["sqs:ListQueues"]
      resources = ["*"]
      condition {
        test     = "StringEquals"
        variable = "aws:RequestedRegion"
        values   = [var.region]
      }
    }
  }
}

resource "aws_iam_role_policy" "provisioner" {
  count = local.enable_aws ? 1 : 0

  name   = "environment-provisioning"
  role   = aws_iam_role.provisioner[0].id
  policy = data.aws_iam_policy_document.provisioner[0].json
}

# Binds (namespace, provider ServiceAccount) -> the provisioning role. This association is the ONLY thing
# that credentials the provider pods (no SA annotation). The provider SA is platform-controlled and never
# used by environment workloads.
resource "aws_eks_pod_identity_association" "provisioner" {
  count = local.enable_aws ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = var.provider_service_account
  role_arn        = aws_iam_role.provisioner[0].arn

  tags = var.tags
}
