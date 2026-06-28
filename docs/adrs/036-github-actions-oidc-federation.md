# ADR-036: GitHub Actions OIDC Federation for CI/CD

**Date:** 2026-05-28

**Status:** Accepted

> **Amendment (2026-06-27, accuracy review).** The implementation snippets below predate the
> registries-as-single-source migration (ADR-061/063/067/069) and the `github_oidc` module interface.
> As-built: the per-team ECR-push roles became **per-Product**, derived from the `Product` registry
> (`gitops/products/**`) — role `github-actions-ecr-push-product-<product>`, ECR scope `team-<team>/<product>-*`,
> branches `["main", "refs/tags/*"]`. `teams.hcl` is retired. Also, the `github_oidc` module exposes only
> `create` / `github_org` / `roles` / `tags`; the flat top-level `github_repo` / `github_branches` /
> `role_name` / `role_policy_arns` shown below are **not** module inputs — per-role attributes live inside the
> `roles` map. And the Terratest `AdministratorAccess` role now carries an explicit Deny overlay
> (`DenyPersistenceEscalationAndGuardrailDisable`) blocking IAM-user/key/federation creation,
> `organizations:*`, `account:*`, and audit/detection teardown. Read the snippets as illustrative-historical.

## Context

CI/CD workflows running in GitHub Actions need AWS API access for ECR image pushes (ADR-028),
Terratest runs, and future deployment automation. The platform operates across multiple AWS
accounts (ADR-004) with an SCP in the Workloads OU (`restrict-iam-users`) that prohibits IAM
access keys. Any CI/CD credential strategy must work within these constraints while minimizing
the blast radius of a compromised workflow.

The platform already uses federated identity patterns — IRSA for pod-level AWS access (ADR-018),
Dex SAML for ArgoCD SSO (ADR-012) — so extending federation to CI/CD is a natural fit.

### Alternatives Considered

**1. Long-lived IAM access keys stored as GitHub Secrets.** The traditional approach: create an
IAM user, generate an access key pair, and store `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`
as repository secrets. Simple to set up, widely documented. However, access keys do not expire
unless manually rotated. A leaked key (e.g., via a compromised action, log exposure, or
repository transfer) provides indefinite access until discovered and revoked. Keys are scoped
to an IAM user, not to a specific repository, branch, or workflow — any workflow that can read
the secret can use the key. This approach is also blocked by the `restrict-iam-users` SCP in
workload accounts, so it would only work in the management or platform accounts where the SCP
does not apply, further limiting its utility.

**2. GitHub OIDC federation with IAM roles (chosen).** GitHub Actions includes a built-in OIDC
identity provider that issues short-lived JWT tokens to workflow runs. AWS trusts GitHub's OIDC
provider via an `aws_iam_openid_connect_provider` resource and allows workflows to assume an
IAM role via `sts:AssumeRoleWithWebIdentity`. The JWT contains claims identifying the repository,
branch, and event type, which the IAM trust policy can filter using `StringLike` conditions on
the `sub` claim. Credentials are short-lived (default 1 hour), scoped to a specific role, and
never stored anywhere. No secrets to rotate, no keys to leak.

**3. Self-hosted GitHub Actions runners with EC2 instance profiles.** Deploy runners on EC2
instances (or EKS pods) with IAM instance profiles attached. Workflows inherit the instance's
IAM role automatically — no credential configuration needed in GitHub. This is the most secure
option (credentials never leave AWS), but adds significant operational overhead: runners must be
provisioned, patched, scaled, and monitored. Runner infrastructure itself becomes a dependency
that must be bootstrapped before CI/CD can function, creating a chicken-and-egg problem for
initial platform deployment. The platform plans to adopt self-hosted runners on EKS in the future,
but OIDC federation provides equivalent security without the infrastructure management burden
for the current scale.

## Decision

Use GitHub Actions OIDC federation for all CI/CD AWS access. The `infra/modules/aws/github_oidc/`
module creates an OIDC identity provider and a scoped IAM role in a single unit. Two deployments
exist today:

### Platform Account: Per-Team ECR Push Roles

Deployed at `infra/live/aws/platform/us-east-1/platform/github-oidc/`. Rather than one shared push
role, the unit generates **one role per team** from the `roles` map — `github-actions-ecr-push-<team>`
— so each role trusts only that team's repo (via the OIDC `sub`) and can push only to that team's
`team-<team>/*` ECR repositories (per-team attribution / ABAC, #61):

```hcl
github_org = "asanexample"

# One push role per team: trusts only that team's repo, pushes only to that team's ECR repos.
roles = { for team, cfg in local.teams :
  "github-actions-ecr-push-${team}" => {
    repos    = [cfg.github_repo] # e.g. ["app-alpha"]
    branches = ["main"]          # push on merge to main
    events   = ["pull_request"]  # and PR preview builds
    tags     = { Team = team }
    inline_policy = jsonencode({ /* ECRAuth (global GetAuthorizationToken) + ECRPush on team-<team>/* */ })
  }
}
```

Each role's inline policy grants `ecr:GetAuthorizationToken` (global) and ECR push actions
(`BatchCheckLayerAvailability`, `PutImage`, `InitiateLayerUpload`, `UploadLayerPart`,
`CompleteLayerUpload`) scoped to that team's repository ARNs only. A compromised CI workflow for one
team therefore cannot push to another team's images — cross-team push is denied at the IAM layer.

Each role's trust policy uses `events = ["pull_request"]` to generate subject claims of the form
`repo:asanexample/<repo>:pull_request` (PR preview builds) plus `branches = ["main"]` for post-merge
image builds.

### Test Account: Terratest Role

Deployed at `infra/live/aws/test/global/github-oidc/`. Creates a role named
`github-actions-terratest` with `AdministratorAccess` for running Terratest integration tests.

```hcl
github_org      = "asanexample"
github_repo     = "platform"
github_branches = ["main", "refs/heads/feat/*"]
role_name       = "github-actions-terratest"
role_policy_arns = ["arn:aws:iam::aws:policy/AdministratorAccess"]
max_session_duration = 3600
```

The trust policy restricts assumption to the `platform` repository on `main` or `feat/*`
branches. `AdministratorAccess` is appropriate here because Terratest creates and destroys real
AWS resources (VPCs, EKS clusters, IAM roles) in the dedicated test account — scoping permissions
would require enumerating every resource type every module might create, which is fragile and
defeats the purpose of integration testing. The test account contains no production workloads
and can be safely torn down and recreated.

### Subject Claim Construction

The module builds subject claims from two sources, concatenated into a single `StringLike`
condition:

1. **Branch claims:** For each repo and branch combination, generates
   `repo:{org}/{repo}:ref:refs/heads/{branch}`. If the branch value already starts with `refs/`,
   it is used as-is (supporting patterns like `refs/heads/feat/*` or `refs/tags/v*`).

2. **Event claims:** For each repo and event combination, generates
   `repo:{org}/{repo}:{event}` (e.g., `repo:asanexample/app-alpha:pull_request`).

This design allows fine-grained control: a role can be restricted to only PR-triggered workflows,
only main branch pushes, or both.

### OIDC Provider Configuration

Each account gets its own `aws_iam_openid_connect_provider` resource pointing to
`https://token.actions.githubusercontent.com` with audience `sts.amazonaws.com`. The thumbprint
is set to the all-`f` sentinel value (`ffffffffffffffffffffffffffffffffffffffff`) because AWS
validates GitHub's OIDC tokens via their JWKS endpoint, not via TLS certificate pinning — the
thumbprint field is required by the API but functionally ignored for OIDC providers that use
HTTPS JWKS endpoints.

## Consequences

### Positive

- No stored credentials — GitHub workflows obtain short-lived STS tokens (default 1-hour
  expiry) via `AssumeRoleWithWebIdentity`. No access keys to rotate, no secrets to leak.
- Branch-scoped access — trust policies restrict role assumption to specific repositories,
  branches, and event types. A workflow running on an unauthorized branch or repository cannot
  assume the role.
- Consistent with SCP enforcement — OIDC federation does not require IAM users or access keys,
  so it works in accounts governed by the `restrict-iam-users` SCP.
- Auditable — every `AssumeRoleWithWebIdentity` call appears in CloudTrail with the full OIDC
  subject claim, providing a clear audit trail from AWS API call back to the specific GitHub
  workflow run, repository, and branch.
- Minimal infrastructure — no runners to manage, no credential rotation automation, no secrets
  manager integration for CI credentials.

### Negative

- One OIDC provider per account — AWS limits each account to a single OIDC provider per issuer
  URL. If another team or service needs GitHub OIDC federation in the same account, they must
  share the provider (the IAM role and trust policy can differ, but the provider resource is
  shared). The module handles this with the `create` variable, allowing additional roles to
  reference an existing provider.
- Fork PRs are blocked by default — GitHub does not issue OIDC tokens to workflows triggered by
  pull requests from forked repositories (the `sub` claim is not populated). This is a security
  feature (forks should not have access to the target repository's AWS resources) but means
  external contributors cannot trigger CI workflows that require AWS access. Mitigated by running
  AWS-dependent tests only on `push` events to branches in the origin repository.
- Trust policy maintenance — each new team/repository that needs CI/CD access requires a new entry
  in the `teams`/`roles` map in the live unit. This is a manual step, unlike a wildcard trust that
  would automatically cover new repositories. The explicit enumeration plus per-team role split is
  intentional (least privilege, no cross-team push) but adds a process step during onboarding.
- `AdministratorAccess` on the Terratest role is broad — a compromised `feat/*` branch workflow
  could perform arbitrary actions in the test account. Mitigated by the test account containing
  no production data and branch protection rules requiring PR review for merges to `main`.
