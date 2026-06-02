locals {
  create = var.create

  # Tenant ECR repositories the provisioning role may manage: "repository/team-*" in the platform account.
  ecr_repo_arn = "arn:aws:ecr:${var.region}:${var.account_id}:repository/${var.tenant_repo_prefix}*"
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
    namespace          = var.namespace
    serviceAccountName = var.provider_service_account
    providerRegistry   = var.provider_registry
    providerVersion    = var.provider_version
    providerServices   = var.provider_services
    waitImage          = var.wait_image
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
    providerConfigName = var.providerconfig_name
  })]

  depends_on = [helm_release.crossplane_runtime]
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
  count = local.create ? 1 : 0

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
  count = local.create ? 1 : 0

  name               = "crossplane-provisioner-${var.cluster_name}"
  description        = "Crossplane AWS provider — tenant resource provisioning (ECR). EKS Pod Identity (ADR-046)."
  assume_role_policy = data.aws_iam_policy_document.assume[0].json
  tags               = var.tags
}

data "aws_iam_policy_document" "provisioner" {
  count = local.create ? 1 : 0

  statement {
    sid    = "TenantEcrRepositories"
    effect = "Allow"
    actions = [
      "ecr:CreateRepository",
      "ecr:DeleteRepository",
      "ecr:DescribeRepositories",
      "ecr:ListTagsForResource",
      "ecr:TagResource",
      "ecr:UntagResource",
      "ecr:PutLifecyclePolicy",
      "ecr:GetLifecyclePolicy",
      "ecr:DeleteLifecyclePolicy",
      "ecr:PutImageScanningConfiguration",
      "ecr:PutImageTagMutability",
      "ecr:SetRepositoryPolicy",
      "ecr:GetRepositoryPolicy",
      "ecr:DeleteRepositoryPolicy",
    ]
    resources = [local.ecr_repo_arn]
  }
}

resource "aws_iam_role_policy" "provisioner" {
  count = local.create ? 1 : 0

  name   = "tenant-provisioning"
  role   = aws_iam_role.provisioner[0].id
  policy = data.aws_iam_policy_document.provisioner[0].json
}

# Binds (namespace, provider ServiceAccount) -> the provisioning role. This association is the ONLY thing
# that credentials the provider pods (no SA annotation). The provider SA is platform-controlled and never
# used by tenant workloads.
resource "aws_eks_pod_identity_association" "provisioner" {
  count = local.create ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = var.provider_service_account
  role_arn        = aws_iam_role.provisioner[0].arn

  tags = var.tags
}
