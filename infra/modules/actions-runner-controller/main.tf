# Actions Runner Controller (ARC) — Autoscaling Runner Scale Sets mode (ADR-065 / #323).
#
# Deploys the ARC controller + a repo-scoped runner scale set onto the platform cluster so an in-VPC runner
# pool exists for CI that must reach the private EKS API. This module gets runners REGISTERED and idle; the
# privileged AWS-creds path (runner Pod Identity → assume PlatformDeployer) + the smoke proof land separately
# so the high-privilege bits review on their own.
#
# Delivered by Terragrunt helm_release like every other platform add-on (NOT ArgoCD — that's for tenant
# workloads). Because ARC is what lets CI manage the cluster, this unit is applied locally / via platctl
# (break-glass): it can't bootstrap itself.

locals {
  create            = var.create
  github_k8s_secret = "arc-github-app" # the K8s secret ARC reads the App creds from (in the runners namespace)
}

# ---------------------------------------------------------------------------
# Namespaces
# ---------------------------------------------------------------------------

resource "kubernetes_namespace_v1" "controller" {
  count = local.create ? 1 : 0
  metadata {
    name   = var.controller_namespace
    labels = { "app.kubernetes.io/managed-by" = "terraform" }
  }
}

resource "kubernetes_namespace_v1" "runners" {
  count = local.create ? 1 : 0
  metadata {
    name   = var.runners_namespace
    labels = { "app.kubernetes.io/managed-by" = "terraform" }
  }
}

# ---------------------------------------------------------------------------
# GitHub App credential (External Secrets → Secrets Manager)
#
# ARC authenticates to GitHub as a GitHub App. The App (created out-of-band — see the runbook) lives in
# Secrets Manager as JSON {appId, installationId, privateKey}; this ExternalSecret projects it into the
# K8s secret `arc-github-app` with the exact keys the gha-runner-scale-set chart expects.
# ---------------------------------------------------------------------------

resource "kubernetes_manifest" "github_app_external_secret" {
  count = local.create ? 1 : 0

  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = local.github_k8s_secret
      namespace = var.runners_namespace
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef  = { name = var.secret_store_name, kind = "ClusterSecretStore" }
      target          = { name = local.github_k8s_secret, creationPolicy = "Owner" }
      data = [
        { secretKey = "github_app_id", remoteRef = { key = var.github_app_secret_name, property = "appId" } },
        { secretKey = "github_app_installation_id", remoteRef = { key = var.github_app_secret_name, property = "installationId" } },
        { secretKey = "github_app_private_key", remoteRef = { key = var.github_app_secret_name, property = "privateKey" } },
      ]
    }
  }

  depends_on = [kubernetes_namespace_v1.runners]
}

# ---------------------------------------------------------------------------
# Runner AWS identity (EKS Pod Identity)
#
# Runner pods get AWS creds via Pod Identity bound to a dedicated, narrowly-scoped role whose only powers are
# to assume PlatformDeployer (providers/secrets/port-forward) and the TerraformStateAccess role (the S3/DynamoDB
# backend — terragrunt assumes it separately) — i.e. exactly what a CI `terragrunt apply` needs, nothing more.
# This is the infra-apply pool's identity; app/CI runner pools must use distinct ones (ADR-065).
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "runner_trust" {
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

resource "aws_iam_role" "runner" {
  count              = local.create ? 1 : 0
  name               = "${var.cluster_name}-arc-runner"
  assume_role_policy = data.aws_iam_policy_document.runner_trust[0].json
  tags               = var.tags
}

# sts:TagSession as well as AssumeRole — terragrunt's exec auth assumes PlatformDeployer with a tagged session.
resource "aws_iam_role_policy" "runner_assume_deployer" {
  count = local.create ? 1 : 0
  name  = "assume-apply-roles"
  role  = aws_iam_role.runner[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        # Providers, secrets, and the keycloak port-forward run as PlatformDeployer.
        Sid      = "AssumePlatformDeployer"
        Effect   = "Allow"
        Action   = ["sts:AssumeRole", "sts:TagSession"]
        Resource = [var.deployer_role_arn]
      },
      {
        # Terragrunt assumes the state role SEPARATELY for the S3/DynamoDB backend (root.hcl remote_state) — in
        # the management account. It uses a TAGGED session (like PlatformDeployer), so sts:TagSession is required
        # alongside AssumeRole; without it a tagged assume 403s on TagSession (state read/lock fails). The state
        # role's trust must also allow sts:TagSession (mgmt/global/state-access).
        Sid      = "AssumeTerraformStateAccess"
        Effect   = "Allow"
        Action   = ["sts:AssumeRole", "sts:TagSession"]
        Resource = [var.state_role_arn]
      },
      ], var.sops_key_arn_pattern == "" ? [] : [{
        # Decrypt the SOPS config key (ADR-066). root.hcl/common.hcl decrypt secrets.enc.yaml at config-eval.
        # The key lives in the management account (cross-account KMS needs the caller's IAM too), scoped to the
        # platform-sops key by alias so this isn't a blanket decrypt on management's keys.
        Sid      = "DecryptSopsConfig"
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:DescribeKey"]
        Resource = [var.sops_key_arn_pattern]
        Condition = {
          "ForAnyValue:StringEquals" = { "kms:ResourceAliases" = var.sops_key_alias }
        }
    }])
  })
}

resource "kubernetes_service_account_v1" "runner" {
  count = local.create ? 1 : 0
  metadata {
    name      = var.runner_service_account
    namespace = var.runners_namespace
  }
  depends_on = [kubernetes_namespace_v1.runners]
}

resource "aws_eks_pod_identity_association" "runner" {
  count           = local.create ? 1 : 0
  cluster_name    = var.cluster_name
  namespace       = var.runners_namespace
  service_account = var.runner_service_account
  role_arn        = aws_iam_role.runner[0].arn
  tags            = var.tags
}

# ---------------------------------------------------------------------------
# ARC controller (gha-runner-scale-set-controller)
# ---------------------------------------------------------------------------

resource "helm_release" "controller" {
  count            = local.create ? 1 : 0
  name             = "arc-controller"
  chart            = "oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller"
  version          = var.controller_chart_version
  namespace        = var.controller_namespace
  create_namespace = false
  timeout          = var.helm_timeout
  wait             = var.helm_wait

  depends_on = [kubernetes_namespace_v1.controller]
}

# ---------------------------------------------------------------------------
# Runner scale set (gha-runner-scale-set)
#
# Registers a repo-scoped scale set named var.runner_scale_set_name — workflows target it via
# `runs-on: <name>`. Runs our custom toolchain image (platform/gha-runner). Scales to zero when idle, no
# docker-in-docker (terragrunt builds no containers, so the runner stays unprivileged).
# ---------------------------------------------------------------------------

resource "helm_release" "runner_set" {
  count            = local.create ? 1 : 0
  name             = var.runner_scale_set_name
  chart            = "oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set"
  version          = var.runner_set_chart_version
  namespace        = var.runners_namespace
  create_namespace = false
  timeout          = var.helm_timeout
  wait             = var.helm_wait

  values = [yamlencode({
    githubConfigUrl    = var.github_config_url
    githubConfigSecret = local.github_k8s_secret
    runnerScaleSetName = var.runner_scale_set_name
    minRunners         = var.min_runners
    maxRunners         = var.max_runners

    # Custom toolchain image (tofu/terragrunt/kubectl/helm/awscli baked in). FROM the official runner base,
    # so the entrypoint is preserved; we only swap the image. The runner SA carries the Pod Identity → AWS.
    template = {
      spec = {
        serviceAccountName = var.runner_service_account
        containers = [{
          name    = "runner"
          image   = var.runner_image
          command = ["/home/runner/run.sh"]
        }]
      }
    }
  })]

  depends_on = [
    helm_release.controller,
    kubernetes_namespace_v1.runners,
    kubernetes_manifest.github_app_external_secret,
    kubernetes_service_account_v1.runner,
    aws_eks_pod_identity_association.runner,
  ]
}
