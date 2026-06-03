locals {
  create = var.create

  # Tenant ECR repositories the provisioning role may manage: "repository/team-*" in the platform account.
  ecr_repo_arn = "arn:aws:ecr:${var.region}:${var.account_id}:repository/${var.tenant_repo_prefix}*"

  enable_aws                 = local.create && length(var.provider_services) > 0
  enable_tenant_provisioning = local.create && var.enable_tenant_provisioning

  # The IAM Pod-team-* roles the provisioning role may create/manage (in this workload account).
  tenant_role_arn_pattern = "arn:aws:iam::${var.account_id}:role/${var.tenant_role_name_prefix}*"

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
    }],
    [for svc in var.provider_services : {
      name                     = "provider-aws-${svc}"
      package                  = "${var.provider_registry}/provider-aws-${svc}:${var.provider_version}"
      serviceAccount           = var.provider_service_account
      hostNetwork              = true
      skipDependencyResolution = true
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
  wait      = var.helm_wait
  atomic    = var.helm_wait

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
    # Cluster constants for the Composition, injected via an EnvironmentConfig (the claim API stays clean).
    environment = {
      ecrRegistry             = var.ecr_registry
      region                  = var.region
      workloadAccountId       = var.account_id
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
      resources = [local.tenant_role_arn_pattern]
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
      resources = [local.tenant_role_arn_pattern]
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
