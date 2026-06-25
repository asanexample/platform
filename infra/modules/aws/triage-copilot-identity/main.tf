# ---------------------------------------------------------------------------
# triage-copilot agent identity (ADR-080) — read-only by construction.
#
# The ONLY AWS permission granted is bedrock:InvokeModel on the Claude inference
# profile. Observability (Loki/Mimir/Tempo) is read over in-cluster HTTP; Kubernetes
# and ArgoCD are read via the in-cluster ServiceAccount RBAC (not IAM). There is NO
# write/remediation permission anywhere in this grant — the "never remediates"
# property of the propose-only agent is an IAM fact, not a prompt instruction.
#
# AWS identity is delivered via EKS Pod Identity (ADR-047): the association below
# binds the agent's ServiceAccount to the role — no IRSA annotation, no OIDC trust.
# The agent WORKLOAD (namespace, ServiceAccount, Deployment, RBAC) is delivered by
# ArgoCD from the app repo; this module provisions ONLY the AWS identity.
# ---------------------------------------------------------------------------

locals {
  create = var.create

  # Cross-region inference needs invoke permission on BOTH the inference-profile ARN
  # and the underlying foundation-model ARNs (empty account segment) it routes to.
  bedrock_invoke_resources = [
    "arn:aws:bedrock:*:${var.aws_account_id}:inference-profile/${var.inference_profile_id}",
    "arn:aws:bedrock:*::foundation-model/${var.foundation_model_id}",
  ]
}

data "aws_iam_policy_document" "trust" {
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

resource "aws_iam_role" "this" {
  count = local.create ? 1 : 0

  name_prefix        = "${var.cluster_name}-triage-copilot-"
  assume_role_policy = data.aws_iam_policy_document.trust[0].json

  tags = var.tags
}

data "aws_iam_policy_document" "bedrock" {
  count = local.create ? 1 : 0

  statement {
    sid       = "InvokeClaude"
    effect    = "Allow"
    actions   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
    resources = local.bedrock_invoke_resources
  }
}

resource "aws_iam_role_policy" "bedrock" {
  count = local.create ? 1 : 0

  name   = "bedrock-invoke"
  role   = aws_iam_role.this[0].id
  policy = data.aws_iam_policy_document.bedrock[0].json
}

resource "aws_eks_pod_identity_association" "this" {
  count = local.create ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = var.service_account
  role_arn        = aws_iam_role.this[0].arn

  tags = var.tags
}
