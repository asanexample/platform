# ADR-026: Cross-Account Secret Isolation

**Date:** 2026-05-24

**Status:** Accepted

## Context

The organization has 5 AWS accounts: the **management** account at the org root, the **Platform OU**
(platform, test), and the **Workloads OU** (preprod, prod) with a **Workloads/Regulated** child OU
reserved for HIPAA-scoped workloads. Each
workload account will eventually host its own EKS cluster with its own External Secrets Operator
deployment (ADR-019). The question is whether secrets should be centralized — one account holds
all secrets, others read cross-account — or isolated, with each account owning its own secrets.

Key constraints that shape this decision:

1. **SCP enforcement.** The Workloads OU has a `restrict-iam-users` SCP that prohibits IAM access
   keys. All authentication must be federated — IRSA (ADR-018) is the only path for pod-level
   secret access.
2. **Data classification.** Prod carries `DataClassification=Confidential`, requiring stricter
   access controls than lower environments.
3. **Regulated workloads.** The Workloads/Regulated OU is reserved for HIPAA-scoped services with
   an optional service allowlist SCP. Cross-account reads from unregulated accounts would violate
   the isolation boundary.
4. **Audit trails.** CloudTrail is per-account. Cross-account reads split the audit trail — the
   source account logs the `GetSecretValue` event, but the calling principal lives in another
   account's trail. Compliance reviewers must correlate across accounts.
5. **IRSA scoping.** Each account has its own EKS cluster with its own OIDC provider and IRSA
   roles. IRSA trust policies are scoped to a single cluster's OIDC issuer — cross-account
   reads require additional resource-based policies on top of IRSA.

### Alternatives Considered

**1. Centralized Secrets Manager in the management account.** All secrets live in one account,
workload accounts read cross-account via resource-based policies with external IDs. Rejected:
the management account should hold governance resources only (Terraform state, Organizations,
Identity Center). Placing application secrets there violates the principle of least privilege
at the account level. A breach of the management account would expose ALL secrets across ALL
environments — the worst possible blast radius.

**2. Centralized in the platform account.** Platform already holds infrastructure-level secrets
(Tailscale OAuth, CloudFlare tokens). Application team secrets from preprod and prod could be
colocated here. Rejected: platform holds platform-level infra secrets, but mixing app team
secrets from preprod/prod violates blast radius isolation. A platform account breach should not
expose prod database credentials. Additionally, platform-to-prod cross-account reads expand the
trust boundary in the wrong direction.

**3. Cross-account reads via resource-based policies (as the default pattern).** Each account
owns its secrets, but workloads in one account can read secrets from another via Secrets Manager
resource-based policies. This is technically straightforward — add a `Principal` condition to
the secret's resource policy. Rejected as the default pattern: each cross-account trust is an
explicit expansion of blast radius. The source account's CloudTrail logs the `GetSecretValue`
call, but the calling principal's identity and context live in another account's trail.
Compliance reviewers must correlate events across accounts. The number of resource-based policies
grows combinatorially as accounts and services scale.

**4. Per-account isolation (chosen).** Each account owns its Secrets Manager instance, its ESO
deployment, and its IRSA roles. No cross-account reads except for a single, explicitly
documented exception class (shared container registry credentials).

## Decision

Adopt per-account secret isolation as the default architecture. Each AWS account owns the full
lifecycle of its secrets — creation, rotation, access, and audit — with no cross-account reads
unless explicitly exempted and documented.

### Architecture

```text
Platform (<PLATFORM_ACCOUNT_ID>)
├── Secrets Manager ─── platform/{service}/{name}
├── ESO ─── ClusterSecretStore (IRSA → this account only)
└── IRSA role: arn:aws:secretsmanager:*:<PLATFORM_ACCOUNT_ID>:secret:*

Preprod (<PREPROD_ACCOUNT_ID>)
├── Secrets Manager ─── {team}/{service}/{name}
├── ESO ─── ClusterSecretStore (IRSA → this account only)
└── IRSA role: arn:aws:secretsmanager:*:<PREPROD_ACCOUNT_ID>:secret:*

Prod (<PROD_ACCOUNT_ID>)
├── Secrets Manager ─── {team}/{service}/{name}
├── ESO ─── ClusterSecretStore (IRSA → this account only)
└── IRSA role: arn:aws:secretsmanager:*:<PROD_ACCOUNT_ID>:secret:*
```

Each ESO deployment's IRSA role is scoped to `arn:aws:secretsmanager:*:${THIS_ACCOUNT_ID}:secret:*`.
The trust policy references only the local cluster's OIDC issuer. There is no IAM path from one
account's ESO to another account's Secrets Manager.

### Secret Values vs. Secret Definitions

Secret **values** are per-environment. A Stripe API key in preprod is a test key; in prod it is
a live key. These are created independently in each account's Secrets Manager.

Secret **definitions** (ExternalSecret CRDs) promote via GitOps. The CRD template is identical
across environments — it references a secret by path (ADR-025) and a SecretStore by name. The
SecretStore backend differs per cluster, pointing at the local account's Secrets Manager. This
means the same ExternalSecret manifest works in all environments without modification.

### Single Exception: Shared Container Registry Credentials

External container registries (e.g., a vendor's private Docker registry) may require the same
credential across all environments. For this case only:

- The credential lives in the platform account under `platform/registry/{registry-name}`
- A Secrets Manager resource-based policy allows `secretsmanager:GetSecretValue` from the
  preprod and prod account ESO IRSA roles
- The policy requires `aws:PrincipalOrgID` as an additional condition
- The exception is documented in the secret's description and in the registry credential's
  ExternalSecret CRD

No other cross-account pattern is permitted without an ADR amendment.

### SCP Alignment

Existing SCPs reinforce per-account isolation without requiring new policies:

- **restrict-iam-users** (Workloads OU): no long-lived credentials (`iam:CreateUser`,
  `iam:CreateAccessKey`, `iam:CreateLoginProfile` denied). IRSA is the only authentication path
  for ESO, and IRSA trust policies are inherently single-account.
- **enforce-encryption** (root, org-wide): enforces KMS encryption at rest for EBS, S3, and RDS
  and includes the `ProtectKmsKeys` statement. Secrets Manager is KMS-encrypted by default
  regardless; the per-account isolation here rests on each account's KMS key being account-scoped,
  so cross-account decryption would require an additional KMS key-policy grant — another layer that
  must be explicitly opened.
- **ProtectKmsKeys** (a statement within `enforce-encryption`): prevents key deletion/disable,
  ensuring secrets remain recoverable.

### Prod-Specific Controls

Prod's `DataClassification=Confidential` tag triggers additional controls:

- **KMS CMK** (not AWS-managed key) for Secrets Manager encryption — enables key policy
  restrictions, rotation control, and CloudTrail logging of key usage
- **CloudTrail data events** for Secrets Manager enabled — logs every `GetSecretValue` call,
  not just management events
- **GHA deploy role** requires environment protection rules (manual approval gate) before any
  Terraform apply that touches secret-related infrastructure

## Consequences

**Positive:**

- Blast radius isolation — a compromise of the preprod account cannot read prod secrets, and
  vice versa. Each account is a hard security boundary, enforced by IAM at the AWS level rather
  than by application-layer access controls.
- Clean audit trails — every `GetSecretValue` call in an account's CloudTrail belongs to a
  principal in that same account. Compliance reviewers audit one account at a time without
  cross-account correlation.
- SCP enforcement without cross-account exceptions — existing SCPs (restrict-iam-users,
  enforce-encryption, ProtectKmsKeys) apply uniformly. No resource-based policy exceptions
  weaken the SCP posture.
- Simpler IAM — no resource-based policies on secrets (except the registry exception), no
  external IDs, no cross-account assume-role chains for secret access.
- Compliance-ready — each account is an audit boundary. Regulated workloads in the
  Workloads/Regulated OU inherit isolation by default with no additional configuration.

**Negative:**

- Secrets cannot be trivially shared across accounts. If a service in preprod and prod needs
  the same credential (beyond the registry exception), it must be created independently in each
  account's Secrets Manager. This is intentional friction but still friction.
- Each account needs its own ESO deployment, IRSA role, and ClusterSecretStore configuration.
  The operational overhead scales linearly with the number of accounts. Mitigated by the shared
  `external-secrets` module (ADR-019) — adding a new account is a new Terragrunt unit, not
  new Terraform code.
- Same secret needed in multiple environments must be created independently per account. There
  is no "promote secret value" workflow — values are set per-account. This is correct for most
  secrets (environment-specific credentials) but adds manual steps for the rare truly-shared
  credential.

**Risks:**

- Teams attempting to work around isolation by hardcoding secrets in Git, passing values through
  Terraform outputs, or storing credentials in SSM Parameter Store (which may have different
  IAM policies). Mitigated by path-scoped IRSA policies (ADR-025 naming convention), code review,
  and onboarding documentation. (There is no SCP restricting `ssm:PutParameter` by path today —
  SSM-path enforcement would be a future Kyverno/CI control, not an org guardrail.)
- The registry exception creates a precedent that teams may try to expand. Each exception request
  must go through the same ADR amendment process. The exception is scoped to read-only access
  for a specific secret path, not a blanket cross-account trust.
- If an account's KMS key is misconfigured or access is lost, secrets in that account become
  unrecoverable. Mitigated by ProtectKmsKeys SCP and KMS key rotation policies.
