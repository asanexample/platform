# ADR-018: IRSA for Pod-Level AWS Identity

**Date:** 2026-05-23

**Status:** Accepted — **narrowed for tenant workloads by [ADR-041](041-pod-identity-for-tenant-workloads.md)** (platform add-ons keep IRSA; *tenant* workloads use EKS Pod Identity).

## Context

Kubernetes workloads running on EKS frequently need to access AWS services — Secrets Manager for
secrets, Route53 for DNS updates, ECR for container images, S3 for storage. Each workload should
authenticate to AWS with the minimum permissions it needs (least privilege), but Kubernetes pods
don't have native AWS identity.

Without a pod-level identity mechanism, the common alternatives all have significant drawbacks:

1. **Node-level IAM role.** Every pod on a node inherits the node's IAM role. All workloads share
   the same permissions — there's no isolation between a DNS updater that needs Route53 access and
   a web server that needs no AWS access at all.

2. **Injected credentials.** AWS access keys stored as Kubernetes Secrets and mounted into pods.
   This requires creating, rotating, and distributing long-lived credentials. Secrets must be
   stored somewhere (Key Vault, Secrets Manager), adding another credential to manage.

3. **kiam/kube2iam.** Community projects that intercept the EC2 metadata endpoint to provide
   per-pod IAM roles. These work but add a proxy in the credential path, have known race conditions
   during node startup, and are largely superseded by AWS's native solution.

### Alternatives Considered

**1. EKS Pod Identity (newer AWS feature).** AWS's second-generation pod identity solution,
launched in late 2023. Uses the EKS Pod Identity Agent (a DaemonSet) instead of OIDC federation.
Simpler to configure — no OIDC provider setup, no `StringEquals` conditions. However, it requires
the Pod Identity Agent add-on, which is another DaemonSet to manage. With BYOCNI (ADR-008), the
agent must be deployed after Cilium and nodes are ready, adding another ordering dependency. IRSA
is already well-understood and doesn't require additional cluster components.

**2. IRSA — IAM Roles for Service Accounts (chosen).** AWS's first-generation native solution.
Uses the EKS cluster's OIDC provider to federate Kubernetes service account tokens with IAM. Each
service account is annotated with an IAM role ARN; when a pod uses that service account, the AWS
SDK automatically exchanges the Kubernetes token for temporary AWS credentials via STS. No
additional agents or sidecars required.

## Decision

Use IRSA (IAM Roles for Service Accounts) for all pod-level AWS access on EKS. Each module that
deploys workloads needing AWS access creates its own IAM role with a trust policy scoped to its
specific service account.

### Implementation Pattern

Every module that uses IRSA follows the same pattern:

```hcl
# 1. Trust policy — only the specific service account can assume this role
data "aws_iam_policy_document" "trust" {
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
    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${var.namespace}:${var.service_account_name}"]
    }
  }
}

# 2. IAM role with the trust policy
resource "aws_iam_role" "this" {
  name               = "${var.cluster_name}-${var.component}"
  assume_role_policy = data.aws_iam_policy_document.trust.json
}

# 3. Permission policies attached to the role
resource "aws_iam_role_policy_attachment" "this" { ... }

# 4. Service account annotated with the role ARN
serviceAccount.annotations = {
  "eks.amazonaws.com/role-arn" = aws_iam_role.this.arn
}
```

### Modules Using IRSA

| Module | Service Account | AWS Permissions |
|--------|----------------|-----------------|
| `argocd` | argocd-server, argocd-repo-server, argocd-application-controller | ECR read-only + custom policies |
| `cert-manager` | cert-manager | Route53 record management (DNS01 validation) |
| `external-dns` | external-dns | Route53 record management |
| `external-secrets` | external-secrets | Secrets Manager + SSM Parameter Store read |

### OIDC Provider

The EKS module automatically creates an OIDC provider for the cluster and exports
`oidc_provider_arn` and `oidc_provider_url`. These outputs are consumed by downstream modules
via Terragrunt dependencies:

```hcl
dependency "eks" {
  config_path = "../eks"
}

inputs = {
  oidc_provider_arn = dependency.eks.outputs.oidc_provider_arn
  oidc_provider_url = dependency.eks.outputs.oidc_provider_url
}
```

### Conditional IRSA

All modules guard IRSA resource creation with a conditional:

```hcl
locals {
  create_irsa = local.create && var.oidc_provider_arn != ""
}
```

This allows the same module to be used on non-EKS clusters (Azure AKS, GCP GKE) where IRSA
doesn't apply. On those platforms, a different identity mechanism (Azure Workload Identity, GCP
Workload Identity) would be configured separately.

## Consequences

**Positive:**

- Fine-grained, per-workload AWS permissions — each pod gets only the IAM permissions it needs
- No long-lived credentials — IRSA uses short-lived STS tokens rotated automatically by the SDK
- No additional agents or DaemonSets — IRSA uses the cluster's built-in OIDC provider
- Trust policy conditions ensure only the specific service account in the specific namespace can
  assume the role — a compromised pod in a different namespace cannot use the credentials
- Standard pattern across all modules — consistent, auditable, easy to review

**Negative:**

- IRSA trust policies are verbose — each role requires an OIDC trust policy document with exact
  service account conditions. This is boilerplate that every module must implement.
- OIDC provider URL must be passed to every module that uses IRSA, creating a dependency on the
  EKS unit from every platform service unit
- IRSA is AWS-specific — Azure and GCP use different pod identity mechanisms (Azure Workload
  Identity, GCP Workload Identity). The module's `create_irsa` conditional handles this but
  means the IRSA code sits unused on non-AWS clusters.

**Risks:**

- If the EKS cluster's OIDC provider is deleted or recreated (e.g., during cluster replacement),
  all IRSA trust policies break because the provider ARN changes. Mitigated by the OIDC provider
  being managed as part of the EKS module — it's only recreated when the cluster itself is
  recreated.
- AWS has a limit of 100 OIDC provider thumbprints and audience values. With current usage (4
  IRSA roles), this is not a concern, but it could become relevant at scale.
