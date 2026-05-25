# ADR-024: Secrets Management Architecture

**Date:** 2026-05-24

**Status:** Accepted

## Context

The platform spans five AWS accounts across three OUs: Management (state, SCPs, billing),
Platform (EKS control plane, shared services), and Workloads (PreProd, Prod, and future Regulated
children). Secrets exist at every lifecycle stage, and each stage has a different delivery
mechanism today:

- **Bootstrap.** Manual env vars (`CLOUDFLARE_API_TOKEN`) and pre-seeded Secrets Manager entries
  (Tailscale API key at `platform/tailscale/api-key`). These are created once by a human before
  any automation runs.
- **Provisioning.** Terraform-managed secrets — Tailscale OAuth credentials created by the
  `tailscale-admin` module and written to Secrets Manager, KMS keys created by the EKS module
  for envelope encryption. These are in Terraform state (encrypted via S3 KMS).
- **Runtime.** Kubernetes workloads needing API keys, database credentials, and service tokens.
  External Secrets Operator is deployed (ADR-019) with IRSA (ADR-018), but no SecretStore or
  ClusterSecretStore CRDs exist yet. Legacy ExternalSecret templates in `charts/secrets/`
  reference superseded patterns.
- **CI/CD.** GitHub Actions authenticates via OIDC federation to an IAM role — no static
  credentials. But CI needs to read secrets during deploy (e.g., Helm values referencing
  Secrets Manager paths).

Several gaps exist in the current state. ESO's IRSA policy is over-permissioned — it can read
all secrets in the platform account rather than being scoped to a path prefix. No naming
convention exists for secrets, leading to inconsistent paths (`platform/tailscale/oauth` vs.
ad hoc names). There is no defined pattern for workload accounts — when PreProd and Prod clusters
come online, each will need its own ESO deployment, IRSA roles, and secret stores.

The workload accounts have a `restrict-iam-users` SCP that blocks `iam:CreateAccessKey` and
`iam:CreateLoginProfile` — all identity must be federated. Prod has
`DataClassification=Confidential` requiring stricter controls: longer recovery windows, mandatory
rotation, and audit logging on all secret access.

### Alternatives Considered

**1. Centralized secrets in the management account with cross-account reads.** Store all secrets
in a single Secrets Manager instance in the management account. Workload accounts read via
cross-account `GetSecretValue` calls using resource-based policies. This simplifies discovery —
all secrets are in one place — and reduces the number of ESO deployments. However, it creates a
massive blast radius: a compromised IRSA role in any cluster could read secrets belonging to
every account. Audit trails become tangled — CloudTrail logs in the management account would mix
access events from all environments. It also violates the account isolation principle that
motivates the OU hierarchy (ADR-005), and the management account should have minimal workloads
running in it.

**2. HashiCorp Vault.** A purpose-built secrets management system with dynamic credentials,
automatic rotation, leasing, and fine-grained audit logging. Vault would centralize secrets
management across clouds and accounts. However, as discussed in ADR-019, Vault requires its own
HA deployment, unsealing procedures, backup/restore, and operational expertise. The BSL licensing
(ADR-016) adds procurement uncertainty. At the platform's current scale (one cluster, small
team), Vault's operational overhead is not justified. If the platform grows to dozens of clusters
or needs dynamic database credentials, Vault should be reconsidered.

**3. Cross-account Secrets Manager reads via resource-based policies.** Individual secrets in
one account are shared to specific IRSA roles in another account using `aws:PrincipalArn`
conditions on the secret's resource policy. This avoids a centralized store while allowing
selective sharing. However, resource-based policies on Secrets Manager are complex to manage at
scale — each shared secret needs its own policy with exact role ARNs, and those ARNs change when
clusters are recreated. As a default pattern, this creates tight coupling between accounts.
Acceptable as an explicit exception for truly shared credentials (e.g., container registry pull
secrets shared from Platform to Workload accounts), but not as the primary architecture.

**4. Per-account secret isolation with ESO + IRSA per cluster (chosen).** Each account owns its
secrets in its own Secrets Manager instance. Each cluster runs its own ESO deployment with an
IRSA role scoped to that account's secrets. No cross-account reads by default. Secrets are
organized by naming convention, and ESO's IAM policy is scoped to the relevant path prefix.
Cross-account sharing is an explicit, documented exception rather than the default.

## Decision

Adopt per-account secret isolation as the default secrets management architecture. Each AWS
account stores its own secrets in its own Secrets Manager instance, and each EKS cluster runs
its own ESO deployment with IRSA scoped to that account's secrets.

### Secret Store Selection

Use AWS Secrets Manager for credentials (API keys, OAuth tokens, database passwords, TLS
private keys) and SSM Parameter Store for non-secret configuration (feature flags, endpoint
URLs, config values that are not sensitive but should not be hardcoded). The distinction:

- **Secrets Manager** — values that would cause a security incident if exposed. Supports
  automatic rotation, versioning, and per-secret resource policies. Costs $0.40/secret/month.
- **SSM Parameter Store** — values that are environment-specific but not sensitive. Free for
  standard parameters (up to 10,000 per account). `SecureString` parameters are available but
  should not be used — if the value is sensitive, it belongs in Secrets Manager.

### Naming Convention

Secrets follow a hierarchical naming pattern that encodes ownership and purpose:

| Account | Pattern | Example |
|---------|---------|---------|
| Platform | `platform/{service}/{name}` | `platform/tailscale/oauth` |
| Platform | `platform/{service}/{name}` | `platform/argocd/dex-saml-cert` |
| PreProd | `{namespace}/{service}/{name}` | `billing/stripe/api-key` |
| Prod | `{namespace}/{service}/{name}` | `billing/stripe/api-key` |

The first path segment identifies the owner: `platform` for platform services in the platform
account, or the Kubernetes namespace for tenant workloads in workload accounts. This maps
directly to ESO's IAM policy scoping — an IRSA role for namespace `billing` can be restricted
to `billing/*` secrets.

SSM parameters use the same convention prefixed with `/config/`:
`/config/platform/argocd/server-url`, `/config/billing/stripe/webhook-endpoint`.

### SecretStore Model

ESO supports two CRD types for connecting to secret backends:

- **ClusterSecretStore** — cluster-wide, can create Kubernetes Secrets in any namespace. Used
  for platform-level secrets that are consumed by platform services across multiple namespaces
  (e.g., ArgoCD, cert-manager, external-dns). One ClusterSecretStore per cluster, backed by a
  single IRSA role with access to `platform/*` secrets.

- **SecretStore** — namespace-scoped, can only create Kubernetes Secrets in its own namespace.
  Used for application team secrets. Each tenant namespace gets its own SecretStore backed by a
  namespace-specific IRSA role scoped to `{namespace}/*` secrets. This prevents one team from
  reading another team's secrets even if they share a cluster.

```text
Cluster
├── ClusterSecretStore (platform)          IRSA: platform/*
│   ├── NS: argocd
│   │   └── ExternalSecret → platform/argocd/dex-saml-cert
│   ├── NS: external-secrets
│   └── NS: cert-manager
│
├── NS: billing
│   ├── SecretStore (billing)              IRSA: billing/*
│   └── ExternalSecret → billing/stripe/api-key
│
└── NS: payments
    ├── SecretStore (payments)             IRSA: payments/*
    └── ExternalSecret → payments/provider/webhook-secret
```

### Identity Model

All secret access uses federated identity — no static credentials anywhere in the chain:

- **ESO to Secrets Manager**: IRSA (ADR-018). The ESO controller's service account is annotated
  with an IAM role ARN. The AWS SDK in the ESO pod exchanges the Kubernetes service account
  token for temporary STS credentials via the cluster's OIDC provider.
- **CI/CD to Secrets Manager**: GitHub Actions OIDC federation. The GitHub Actions workflow
  assumes an IAM role via `aws-actions/configure-aws-credentials` with OIDC — no access keys.
- **Human access**: AWS SSO (Identity Center). Operators access Secrets Manager via the console
  or CLI using temporary SSO session credentials.
- **Cross-account (exceptions only)**: Resource-based policies on individual secrets with
  `aws:PrincipalArn` conditions. Documented in the secret's description field.

The `restrict-iam-users` SCP in workload accounts enforces this — `iam:CreateAccessKey` is
denied, so static credentials cannot be created even accidentally.

### ESO IRSA Scoping

The current ESO IRSA policy is over-permissioned. The updated policy scopes access to the
account's secret path prefix:

```json
{
  "Effect": "Allow",
  "Action": [
    "secretsmanager:GetSecretValue",
    "secretsmanager:DescribeSecret"
  ],
  "Resource": "arn:aws:secretsmanager:*:ACCOUNT_ID:secret:platform/*"
}
```

For workload accounts with namespace-scoped SecretStores, each IRSA role is scoped to its
namespace prefix:

```json
{
  "Resource": "arn:aws:secretsmanager:*:ACCOUNT_ID:secret:billing/*"
}
```

### Recovery and Rotation

Secret deletion recovery windows vary by environment to balance safety and operational speed:

| Environment | Recovery Window | Rationale |
|-------------|----------------|-----------|
| Dev/Test | 0 days (immediate) | Fast iteration, no compliance requirements |
| Platform | 7 days | Allow rollback of accidental deletions |
| Prod | 30 days | Compliance requirement, DataClassification=Confidential |

ESO refresh intervals control how quickly rotated secrets propagate to Kubernetes:

| Secret Type | Refresh Interval | Example |
|-------------|-----------------|---------|
| Static (manual rotation) | 24h | SAML certificates, API keys with no expiry |
| Standard | 1h | API keys, OAuth tokens with known rotation schedule |
| Auto-rotated | 15m | Database passwords rotated by Secrets Manager |

### Multi-Cloud Portability

The per-account isolation pattern maps directly to Azure:

| AWS | Azure |
|-----|-------|
| AWS Secrets Manager | Azure Key Vault |
| IRSA (OIDC federation) | Workload Identity (OIDC federation) |
| SecretStore (Secrets Manager backend) | SecretStore (Azure Key Vault backend) |
| Per-account isolation | Per-subscription isolation |

The ExternalSecret CRDs are identical across clouds — only the SecretStore backend
configuration changes. This is the same portability model as Cilium (ADR-008) and ESO
(ADR-019): cloud-agnostic workload interface, cloud-specific infrastructure backend.

## Consequences

**Positive:**

- Blast radius is contained per account — a compromised IRSA role in PreProd cannot read Prod
  secrets, even if the attacker has full control of the ESO controller
- Audit trail is clear — CloudTrail logs in each account show exactly which IRSA role accessed
  which secrets, with no cross-account noise
- Aligns with SCP enforcement — workload accounts block static credentials via
  `restrict-iam-users`, and this architecture requires only federated identity
- Naming convention enables IAM policy scoping — `{namespace}/*` prefixes allow least-privilege
  policies without enumerating individual secret ARNs
- Multi-cloud portable — Azure Key Vault + Workload Identity is the same pattern with different
  backend configuration, keeping ExternalSecret CRDs identical across clouds
- Namespace-scoped SecretStores provide tenant isolation within shared clusters — one team
  cannot read another team's secrets even with kubectl access to the cluster

**Negative:**

- Operational overhead of per-account ESO — each cluster needs its own ESO deployment, IRSA
  role, and SecretStore CRDs. For N clusters across M accounts, this is N ESO deployments to
  monitor and upgrade.
- Secrets cannot be shared across accounts without an explicit exception (resource-based
  policy). Shared credentials (e.g., container registry pull secrets) require additional
  configuration and documentation.
- Per-namespace IRSA roles in workload accounts create IAM role sprawl — each tenant namespace
  needs its own role. At scale (dozens of namespaces), this adds IAM management burden.
- Naming convention must be enforced socially or via policy (Kyverno, ADR-014) — nothing in
  Secrets Manager prevents creating a secret with a non-conforming name.

**Risks:**

- ESO controller failure. If the ESO pod is down or crashlooping, existing Kubernetes Secrets
  persist (they are materialized resources), but rotated secrets will not propagate and new
  ExternalSecrets will not sync. Mitigated by monitoring ESO pod health, setting up alerts on
  `externalsecret_sync_failure` metrics, and running ESO with multiple replicas.
- Secret sprawl. Without a cleanup process, deleted applications may leave orphaned secrets in
  Secrets Manager. The recovery window prevents immediate deletion, but abandoned secrets still
  incur cost ($0.40/secret/month) and clutter the namespace. Mitigated by including secret
  cleanup in application offboarding runbooks.
- Cross-account exception creep. The "explicit exception" model for cross-account reads works
  at small scale, but if many secrets end up shared, the architecture drifts toward the
  centralized model (Alternative 1). Mitigated by reviewing cross-account policies quarterly
  and treating each one as a tech debt item to eliminate.
- IRSA role recreation. If a cluster is destroyed and recreated, IRSA role ARNs change (the
  OIDC provider URL is cluster-specific). Any cross-account resource-based policies referencing
  the old role ARN will break. Mitigated by documenting cross-account policies and including
  them in cluster recreation runbooks.
