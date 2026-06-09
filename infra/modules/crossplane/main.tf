locals {
  create = var.create

  # Tenant ECR repositories the provisioning role may manage: "repository/team-*" in the platform account.
  ecr_repo_arn = "arn:aws:ecr:${var.region}:${var.account_id}:repository/${var.tenant_repo_prefix}*"

  enable_aws                 = local.create && length(var.provider_services) > 0
  enable_tenant_provisioning = local.create && var.enable_tenant_provisioning

  # The IAM Pod-team-* roles the provisioning role may create/manage (in this workload account). PassRole is
  # scoped to these only (the workload roles handed to EKS Pod Identity).
  tenant_role_arn_pattern = "arn:aws:iam::${var.account_id}:role/${var.tenant_role_name_prefix}*"

  # Roles the provisioning role may create/manage: the Pod-team-* workload roles AND the DeveloperAccess-*
  # per-team developer-access roles (P2c). Both name prefixes, same account.
  manageable_role_arn_patterns = [
    local.tenant_role_arn_pattern,
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
}

# ---------------------------------------------------------------------------
# Crossplane core (control plane)
# ---------------------------------------------------------------------------
# Installed as a Terragrunt-managed Helm add-on, like every other platform service (Kyverno, cert-manager,
# Cilium). Crossplane is the *tenant* control plane (ADR-046); foundational/platform infra stays on
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
    namespace   = var.namespace
    waitImage   = var.wait_image
    providers   = local.providers
    functions   = var.functions
    waitForCrds = local.wait_for_crds
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
  })]

  depends_on = [helm_release.crossplane_runtime]
}

# ---------------------------------------------------------------------------
# Tenant API (local chart): the Tenant XRD + Composition + the shared tenant-developer ClusterRole
# ---------------------------------------------------------------------------
# Workload clusters only (ADR-048). The Composition (function-go-templating) renders a tenant's Kubernetes
# resources via provider-kubernetes. Applied after config so the kubernetes ProviderConfig + the function
# exist. Crossplane core validates XRD/Composition at admission — see the README note on the overlay webhook.

resource "helm_release" "crossplane_tenant" {
  count = local.create && var.enable_tenant_api ? 1 : 0

  name      = "crossplane-tenant"
  chart     = "${path.module}/charts/tenant"
  namespace = var.namespace
  timeout   = var.helm_timeout
  wait      = var.helm_wait
  atomic    = var.helm_wait

  values = [yamlencode({
    providerConfigName = var.providerconfig_name
    # The shared tenant-developer ClusterRole the Composition's per-tenant RoleBindings reference. The retired v1
    # `tenant` module used to own it (coexistence → default false); on a fresh v2 build the tenant chart creates it.
    createDeveloperClusterRole = var.create_developer_cluster_role
    # Cluster constants for the Composition, injected via an EnvironmentConfig (the claim API stays clean).
    environment = {
      ecrRegistry             = var.ecr_registry
      baseDomain              = var.base_domain
      region                  = var.region
      workloadAccountId       = var.account_id
      managementAccountId     = var.management_account_id
      clusterName             = var.cluster_name
      pullAccountIds          = var.tenant_pull_account_ids
      permissionsBoundaryArn  = local.enable_tenant_provisioning ? aws_iam_policy.tenant_boundary[0].arn : ""
      providerConfigEcr       = var.ecr_provisioner_role_arn != "" ? "platform-ecr" : var.providerconfig_name
      podIdentityServiceAccnt = var.provider_service_account
    }
  })]

  depends_on = [helm_release.crossplane_config]
}

# ---------------------------------------------------------------------------
# Team registry projection (local chart): canonical Team records -> projected Team CRs
# ---------------------------------------------------------------------------
# The envelope subset Kyverno's restrict-tenant-envelope reads during XTenant admission (ADR-049 A2). After
# the tenant chart so the Team CRD exists. Default empty (var.teams = {}) renders nothing — additive.

resource "helm_release" "crossplane_teams" {
  count = local.create && var.enable_tenant_api ? 1 : 0

  name      = "crossplane-teams"
  chart     = "${path.module}/charts/teams"
  namespace = var.namespace
  timeout   = var.helm_timeout
  wait      = var.helm_wait
  atomic    = var.helm_wait

  values = [yamlencode({ teams = var.teams })]

  depends_on = [helm_release.crossplane_tenant]
}

# ---------------------------------------------------------------------------
# Tenant control-plane Kyverno policies (local chart)
# ---------------------------------------------------------------------------
# restrict-tenant-envelope (ADR-049) + restrict-tenant-control-plane (ADR-046/048). They match Crossplane
# CRDs — XTenant, the projected Team, and the provider ProviderConfigs — so they live with the tenant control
# plane, NOT in the policy unit. The policy unit deploys BEFORE crossplane (it must, to pre-create the
# crossplane-system Kyverno exclusion), so if these two policies shipped there Kyverno would churn its webhook
# config resolving the not-yet-existing XTenant/ProviderConfig kinds — which is exactly what stalled the preprod
# `policy` install (a single transient validate-policy webhook timeout rolling the whole bundle back). Installed
# here, after crossplane_teams, every kind they match already exists, so admission registration is clean.
#
# Gated on enable_tenant_api (workload clusters): where there's no tenant control plane there's no XTenant CRD
# and ProviderConfigs are platform-managed only, so neither policy has anything to guard.
resource "helm_release" "crossplane_tenant_policies" {
  count = local.create && var.enable_tenant_api ? 1 : 0

  name      = "crossplane-tenant-policies"
  chart     = "${path.module}/charts/tenant-policies"
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
  # unit can override (e.g. envelopeFailureAction=Enforce at the A6 cutover) via var.tenant_policy_values.
  values = [yamlencode(var.tenant_policy_values)]

  depends_on = [helm_release.crossplane_teams]
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
    # ProviderConfigs). XRD/Composition/EnvironmentConfig (tenant chart), Provider/Function/Configuration +
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
    helm_release.crossplane_tenant,
    helm_release.crossplane_teams,
    helm_release.crossplane_tenant_policies,
  ]
}

# ---------------------------------------------------------------------------
# Teardown: sweep orphaned Crossplane-provisioned tenant IAM roles (AWS-side)
# ---------------------------------------------------------------------------
# crd_finalizer_cleanup (above) drains the IN-CLUSTER Crossplane CRs so the helm uninstalls succeed — but
# uninstalling Crossplane never deletes the EXTERNAL AWS resources its Composition created. The per-tenant
# Pod-<...> workload roles and the DeveloperAccess-<team> roles persist with this deny-escalation boundary
# attached as their PermissionsBoundary, so aws_iam_policy.tenant_boundary then fails to delete ("DeleteConflict:
# Cannot delete a policy attached to entities"), failing the whole unit teardown (observed on preprod). This
# sweep deletes exactly those roles (only ones carrying this boundary — by the S2 condition the provisioner can
# create roles ONLY with it, so every match is a tenant role). It depends_on the boundary, so its when=destroy
# provisioner runs BEFORE the boundary is deleted (reverse-order destroy). The script always exits 0 — best-effort,
# never blocks destroy. Reuses the scripts/ dir of finalizer_clear_script so no extra unit wiring is needed.
resource "null_resource" "tenant_iam_orphan_sweep" {
  count = local.enable_tenant_provisioning ? 1 : 0

  triggers = {
    script       = "${dirname(var.finalizer_clear_script)}/tenant-iam-orphan-sweep.sh"
    boundary_arn = aws_iam_policy.tenant_boundary[0].arn
    region       = var.region
    role_arn     = var.deployer_role_arn
  }

  provisioner "local-exec" {
    when    = destroy
    command = "bash ${self.triggers.script} ${self.triggers.boundary_arn} ${self.triggers.region} ${self.triggers.role_arn}"
  }
}

# Sibling of the IAM sweep for the cross-account tenant ECR repos (team-<team>/<app>) the Composition created
# in the platform account. Uninstalling Crossplane orphans them too; they don't block teardown (a rebuild
# re-adopts them by external-name), but a clean teardown removes them so each cycle starts pristine. Gated on a
# sweep role being provided (the platform PlatformDeployer — the in-account ecr-provisioner role is NOT
# assumable by the teardown profile, only via the provider's assumeRoleChain). Best-effort; never blocks destroy.
resource "null_resource" "tenant_ecr_orphan_sweep" {
  count = local.enable_tenant_provisioning && var.ecr_orphan_sweep_role_arn != "" ? 1 : 0

  triggers = {
    script   = "${dirname(var.finalizer_clear_script)}/tenant-ecr-orphan-sweep.sh"
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
# The AWS provider assumes this role to provision tenant resources. P1 scope: ECR repositories under
# "team-*" only (the demo + the eventual per-team ECR repos). Later phases EXTEND this policy (IAM roles +
# Pod Identity associations for the Tenant Composition) — at which point a permissions boundary on
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
  description        = "Crossplane AWS provider - tenant resource provisioning (ECR). EKS Pod Identity (ADR-046)."
  assume_role_policy = data.aws_iam_policy_document.assume[0].json
  tags               = var.tags
}

# ---------------------------------------------------------------------------
# Deny-escalation permissions boundary (P2b) — the cap on every Crossplane-created Pod-team role.
# ---------------------------------------------------------------------------
# Effective tenant-role perms = (the role's declared policy) ∩ (this boundary). Even if the provisioning
# identity is tricked into attaching admin, the boundary keeps a tenant role from privilege escalation.
data "aws_iam_policy_document" "tenant_boundary" {
  count = local.enable_tenant_provisioning ? 1 : 0

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

resource "aws_iam_policy" "tenant_boundary" {
  count = local.enable_tenant_provisioning ? 1 : 0

  name        = "tenant-permissions-boundary-${var.cluster_name}"
  description = "Deny-escalation boundary attached to every Crossplane-provisioned Pod-team-* role (S2)."
  policy      = data.aws_iam_policy_document.tenant_boundary[0].json
  tags        = var.tags
}

data "aws_iam_policy_document" "provisioner" {
  count = local.enable_aws ? 1 : 0

  # Platform hub (P1): ECR repositories provisioned LOCALLY. Not used on a tenant-provisioning workload
  # cluster (preprod), where ECR is cross-account (via the assumed platform role below).
  dynamic "statement" {
    for_each = local.enable_tenant_provisioning ? [] : [1]
    content {
      sid    = "TenantEcrRepositoriesLocal"
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

  # Tenant provisioning (workload cluster): create Pod-team-* roles ONLY with the boundary attached.
  dynamic "statement" {
    for_each = local.enable_tenant_provisioning ? [1] : []
    content {
      sid       = "TenantIamCreateRoleBoundedOnly"
      effect    = "Allow"
      actions   = ["iam:CreateRole"]
      resources = local.manageable_role_arn_patterns
      condition {
        test     = "StringEquals"
        variable = "iam:PermissionsBoundary"
        values   = [aws_iam_policy.tenant_boundary[0].arn]
      }
    }
  }
  # Manage the created roles (NO Put/DeleteRolePermissionsBoundary → cannot strip the boundary).
  dynamic "statement" {
    for_each = local.enable_tenant_provisioning ? [1] : []
    content {
      sid    = "TenantIamManageRoles"
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
  # PassRole the tenant roles to EKS Pod Identity only.
  dynamic "statement" {
    for_each = local.enable_tenant_provisioning ? [1] : []
    content {
      sid       = "TenantIamPassRole"
      effect    = "Allow"
      actions   = ["iam:PassRole"]
      resources = [local.tenant_role_arn_pattern]
      condition {
        test     = "StringEquals"
        variable = "iam:PassedToService"
        values   = ["pods.eks.amazonaws.com"]
      }
    }
  }
  # EKS Pod Identity associations on this cluster.
  dynamic "statement" {
    for_each = local.enable_tenant_provisioning ? [1] : []
    content {
      sid    = "TenantPodIdentityAssociations"
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
    for_each = local.enable_tenant_provisioning ? [1] : []
    content {
      sid    = "TenantEksAccessEntries"
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
  # Assume the platform-account role to provision tenant ECR repos cross-account.
  dynamic "statement" {
    for_each = local.enable_tenant_provisioning && var.ecr_provisioner_role_arn != "" ? [1] : []
    content {
      sid    = "AssumePlatformEcrProvisioner"
      effect = "Allow"
      # provider-upjet-aws passes session tags on the assumeRoleChain hop, so the chain needs sts:TagSession
      # alongside sts:AssumeRole (the target role's trust policy must allow sts:TagSession too).
      actions   = ["sts:AssumeRole", "sts:TagSession"]
      resources = [var.ecr_provisioner_role_arn]
    }
  }
}

resource "aws_iam_role_policy" "provisioner" {
  count = local.enable_aws ? 1 : 0

  name   = "tenant-provisioning"
  role   = aws_iam_role.provisioner[0].id
  policy = data.aws_iam_policy_document.provisioner[0].json
}

# Binds (namespace, provider ServiceAccount) -> the provisioning role. This association is the ONLY thing
# that credentials the provider pods (no SA annotation). The provider SA is platform-controlled and never
# used by tenant workloads.
resource "aws_eks_pod_identity_association" "provisioner" {
  count = local.enable_aws ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = var.provider_service_account
  role_arn        = aws_iam_role.provisioner[0].arn

  tags = var.tags
}
