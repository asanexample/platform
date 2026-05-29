# ADR-028: ECR Cross-Account Container Registry

**Date:** 2026-05-27

**Status:** Accepted

## Context

The platform operates across four AWS accounts (ADR-004): management (<MGMT_ACCOUNT_ID>), platform
(<PLATFORM_ACCOUNT_ID>), preprod (<PREPROD_ACCOUNT_ID>), and prod (<PROD_ACCOUNT_ID>). Application teams build container
images in CI pipelines (GitHub Actions) and deploy them to EKS clusters running in preprod and
prod. The platform needs a container registry strategy that satisfies three constraints:

1. **Image provenance.** A single source of truth for container images ensures that the exact
   image digest deployed in preprod is the same one promoted to prod. Image "promotion" should
   not involve rebuilding — the same artifact must be deployable across environments.

2. **Cross-account access.** Pods in preprod and prod EKS clusters must be able to pull images
   without long-lived credentials. The Workloads OU has a `restrict-iam-users` SCP that prohibits
   IAM access keys — all authentication must be federated or use instance-level credentials.

3. **CI/CD push access.** GitHub Actions workflows must push images to the registry without
   storing AWS credentials in GitHub Secrets. The platform already has a `github_oidc` module
   (`infra/modules/aws/github_oidc/`) that creates OIDC federation between GitHub Actions and
   AWS IAM, providing short-lived STS credentials for CI workflows.

4. **Lifecycle management.** Untagged and old images must be cleaned up automatically to prevent
   unbounded storage growth and cost.

### Alternatives Considered

**1. ECR per account.** Each AWS account (platform, preprod, prod) hosts its own ECR repositories.
Images built in CI are pushed to all accounts, or pushed to one and "promoted" by re-tagging and
pushing to others. This provides strong isolation — each account's images are independent — but
creates duplication. The same image is stored 2-3 times across accounts. "Promotion" requires
either cross-account `docker pull` + `docker push` (adding CI complexity and a credential for
each target account) or ECR replication rules (which create asynchronous copies with eventual
consistency, meaning a deploy can race the replication). Image digest identity across environments
is not guaranteed unless the same manifest is pushed byte-for-byte.

**2. Centralized ECR in platform account with cross-account pull (chosen).** All repositories
live in the platform account (<PLATFORM_ACCOUNT_ID>). CI pushes once. Preprod and prod pull the same
image by digest. Cross-account access is granted via ECR repository policies that allow
`ecr:BatchGetImage`, `ecr:GetDownloadUrlForLayer`, and `ecr:BatchCheckLayerAvailability` to
the preprod and prod account root principals. No credentials are stored in workload accounts —
node IAM roles already include `AmazonEC2ContainerRegistryReadOnly`, which grants the ECR auth
token retrieval needed to pull cross-account images when combined with the repository policy.

**3. Public registry (GHCR or Docker Hub).** Push images to GitHub Container Registry or Docker
Hub. No cross-account IAM complexity — images are pulled over HTTPS with optional authentication.
However, this introduces an external dependency on a third-party service for production
deployments. Private images require storing registry credentials as Kubernetes Secrets in every
cluster, which contradicts the IRSA-based credential model (ADR-018). Public images expose
internal application code. Network egress costs and pull rate limits (Docker Hub) add operational
risk.

**4. Self-hosted registry on Kubernetes.** Deploy Harbor, Distribution (Docker Registry v2), or
Zot on the platform EKS cluster. Full control over the registry, no cloud vendor lock-in. However,
this adds significant operational overhead: the registry becomes a critical-path dependency that
must be highly available, backed up, and monitored. Storage must be provisioned (EBS or S3 via
CSI driver). Authentication and authorization must be implemented separately. The registry itself
becomes a workload that needs resource quotas, monitoring, and upgrade procedures. For the current
scale (2-3 teams, <50 repositories), this overhead is not justified.

## Decision

Use centralized ECR repositories in the platform account (<PLATFORM_ACCOUNT_ID>) with cross-account pull
access for preprod and prod. The `infra/modules/aws/ecr/` module manages repository creation,
cross-account policies, and lifecycle rules. The ECR live unit is deployed at
`infra/live/aws/platform/us-east-1/platform/ecr/`.

### Repository Structure

Repositories follow a `{team}/{app}` naming convention, matching the tenant structure (ADR-027):

```hcl
repositories = {
  "team-alpha/app" = {}
  "team-bravo/app" = {}
}
```

Teams can have multiple repositories (e.g., `team-alpha/api`, `team-alpha/worker`).

### Cross-Account Pull Access

The ECR module creates a repository policy on each repository that grants pull permissions to
specified account root principals:

```hcl
pull_account_ids = ["<PREPROD_ACCOUNT_ID>", "<PROD_ACCOUNT_ID>"]  # preprod, prod
```

The repository policy grants `ecr:BatchGetImage`, `ecr:GetDownloadUrlForLayer`, and
`ecr:BatchCheckLayerAvailability` — scoped to the repository level, so access can be granted
or revoked per-repository.

EKS managed node groups use the `AmazonEC2ContainerRegistryReadOnly` managed policy, which
grants `ecr:GetAuthorizationToken` (required to obtain a Docker auth token for any ECR registry
in any account) plus read permissions on the local account's repositories. Combined with the
cross-account repository policy, nodes can authenticate and pull from the platform account's
ECR without additional configuration.

### CI Push Access

GitHub Actions authenticates to the platform account via OIDC federation using the `github_oidc`
module. The CI workflow assumes an IAM role with ECR push permissions scoped to the team's
repositories. No AWS access keys are stored in GitHub — the OIDC trust policy restricts the
role to specific repository and branch patterns.

### Image Tag Immutability

All repositories are created with `image_tag_mutability = "IMMUTABLE"`. Once an image is pushed
with a tag (e.g., `v1.2.3`), that tag cannot be reassigned to a different image digest. This
enforces:

- **Reproducible deployments** — `v1.2.3` always refers to the same image, regardless of when
  or where it is pulled
- **Audit trail integrity** — the image running in prod is provably the same artifact that was
  tested in preprod
- **No accidental overwrites** — a CI pipeline cannot silently replace a production image by
  pushing to an existing tag

Mutable tags (e.g., `latest`) are not used. Kubernetes manifests must reference specific image
tags or digests.

### Lifecycle Policies

The ECR module applies two lifecycle rules to every repository:

1. **Expire untagged images after 7 days.** Intermediate build layers and failed pushes are
   cleaned up automatically. The 7-day window allows debugging failed builds without retaining
   artifacts indefinitely.

2. **Keep last 50 tagged images.** Older tagged images beyond the retention count are expired.
   This prevents unbounded storage growth while retaining enough history for rollbacks. At a
   typical release cadence of 2-3 deploys per week, 50 images covers approximately 4-6 months
   of history.

Both rules are applied per-repository. The `max_image_count` variable (default: 50) is
configurable if a team needs more or fewer retained images.

### Image Scanning and Encryption

All repositories enable `scan_on_push = true` for automated vulnerability scanning on every
push. Repositories use `AES256` (S3-managed) encryption at rest. If prod images require
`DataClassification=Confidential` (ADR-026), encryption can be upgraded to KMS CMK per-repository.

## Consequences

### Positive

- Single source of truth — one repository per application, one image push per build. The same
  image digest is pulled in preprod and prod, eliminating "works in staging but not in prod"
  class of deployment issues.
- No image promotion workflow — "promotion" is a Kubernetes manifest change pointing at the same
  image tag/digest, not a registry operation. No cross-account push credentials, no replication
  lag, no digest mismatches.
- No credentials in workload accounts — nodes authenticate via instance IAM roles, pods pull
  images via the node's Docker credential chain. No Kubernetes Secrets storing registry
  credentials.
- Lifecycle policies prevent unbounded storage growth — untagged images expire after 7 days,
  tagged images beyond the retention count are pruned automatically.
- Tag immutability provides audit trail integrity and prevents accidental overwrites of
  production images.
- Consistent with SCP enforcement — no IAM access keys needed in workload accounts for image
  pulls. OIDC federation for CI pushes aligns with the `restrict-iam-users` SCP.

### Negative

- Single point of failure — if the platform account's ECR is unavailable, no account can pull
  images. EKS nodes cache pulled images locally, so running pods are unaffected, but new pod
  scheduling or rollouts would fail. Mitigated by ECR's regional SLA (99.9%) and the fact that
  a full ECR outage would affect all AWS customers, not just this platform.
- Cross-account repository policies grant pull access to the entire account root principal, not
  specific IAM roles. Any principal in the preprod or prod account that can obtain an ECR auth
  token can pull any image from the platform account's ECR. This is acceptable because
  `AmazonEC2ContainerRegistryReadOnly` is only attached to node IAM roles, and the Workloads OU
  SCP prevents creating new IAM users or access keys.
- Repository creation requires platform team intervention — teams cannot self-service create
  new ECR repositories. This is intentional (the platform team controls the namespace and
  lifecycle policies) but adds a process step for onboarding new applications.

### Risks

- If the GitHub OIDC trust policy is misconfigured, unauthorized repositories or branches could
  push images to ECR. Mitigated by scoping the trust policy to specific `repo:org/repo:ref:`
  patterns and reviewing trust policies during CI pipeline onboarding.
- A compromised CI pipeline could push a malicious image with a new tag. Tag immutability
  prevents overwriting existing tags, but new tags are unrestricted. Mitigated by ECR scan-on-
  push (detects known CVEs) and future image signing with cosign/Sigstore for supply chain
  verification.
- The 50-image retention limit may be too aggressive for teams with frequent releases or too
  generous for teams with infrequent releases. The `max_image_count` variable allows per-team
  tuning, but the default applies uniformly. Teams that exhaust their history window lose the
  ability to roll back to older releases.
- If a new AWS account is added to the organization (e.g., a staging account), the ECR
  `pull_account_ids` list must be updated manually. Forgetting this step means pods in the new
  account cannot pull images. Mitigated by documenting the ECR unit as part of the new-account
  onboarding checklist.
