# ADR-019: External Secrets Operator for Secrets Management

**Date:** 2026-05-23

**Status:** Accepted

## Context

Kubernetes workloads need access to secrets — API keys, database credentials, OAuth tokens, TLS
certificates. Kubernetes has a built-in Secret resource, but it stores values as base64-encoded
plaintext in etcd. Secrets must come from somewhere, and the mechanism for getting them into the
cluster has significant security implications.

The platform currently stores secrets in AWS Secrets Manager (e.g., Tailscale OAuth credentials at
`platform/tailscale/oauth`). These secrets need to flow into Kubernetes without being checked into
version control or manually applied via kubectl.

### Alternatives Considered

**1. Kubernetes Secrets created by Terraform.** Use `kubernetes_secret` resources in Terraform to
create secrets directly. The secret values would be in Terraform state (encrypted at rest via S3
KMS). This works but tightly couples secret lifecycle to infrastructure lifecycle — rotating a
secret requires a Terraform apply. Secrets in Terraform state are also visible to anyone with
state access, even if they don't need the secret values.

**2. Sealed Secrets (Bitnami).** Encrypt secrets client-side with a cluster-specific public key,
commit the encrypted `SealedSecret` to Git, and a controller decrypts them in-cluster. Enables
GitOps for secrets. However, the encryption key is per-cluster — secrets must be re-encrypted
when clusters are recreated. There's no integration with cloud secret stores, so secrets must be
manually managed in two places (cloud store and Git).

**3. HashiCorp Vault.** Full-featured secrets management with dynamic credentials, leases, and
audit logging. The gold standard for secrets management. However, Vault is a complex system that
requires its own HA deployment, unsealing procedures, and operational expertise. For a small
platform team, the operational overhead outweighs the benefits at current scale. Also subject to
the same BSL licensing concerns as Terraform (see ADR-016).

**4. External Secrets Operator (chosen).** A Kubernetes operator that synchronizes secrets from
external secret stores (AWS Secrets Manager, Azure Key Vault, GCP Secret Manager, etc.) into
Kubernetes Secrets. Declarative — an `ExternalSecret` CRD specifies which secret to fetch and
where to store it. Uses IRSA (ADR-018) for AWS authentication. Cloud-agnostic model with
cloud-specific SecretStore backends.

## Decision

Deploy the External Secrets Operator (ESO) on all Kubernetes clusters for synchronizing secrets
from cloud secret stores into Kubernetes. The module (`infra/modules/external-secrets/`) installs
ESO via Helm and configures IRSA for AWS Secrets Manager access.

### Architecture

```text
AWS Secrets Manager                    Kubernetes Cluster
┌──────────────────┐                  ┌────────────────────────┐
│ platform/        │    IRSA (STS)    │ ExternalSecret CRD     │
│   tailscale/     │ ◄────────────── │   → references secret  │
│     oauth        │                  │   → specifies target   │
└──────────────────┘                  │                        │
                                      │ ESO Controller         │
                                      │   → fetches secret     │
                                      │   → creates K8s Secret │
                                      └────────────────────────┘
```

### IRSA Configuration

The ESO module creates an IRSA role (ADR-018) scoped to:

- `secretsmanager:GetSecretValue` on secrets matching the platform's naming pattern
- `ssm:GetParameter` for SSM Parameter Store values

The trust policy restricts assumption to the `external-secrets` service account in the
`external-secrets` namespace.

### SecretStore Model

ESO supports two CRD types:

- `SecretStore` — namespace-scoped, can only create secrets in its own namespace
- `ClusterSecretStore` — cluster-wide, can create secrets in any namespace

The platform currently uses module-level secret fetching (Terragrunt `run_cmd` or generated data
sources) rather than ExternalSecret CRDs. The ESO deployment prepares the infrastructure for
migrating to the declarative ExternalSecret model as more services are onboarded.

### Helm Chart Version

The chart version is centrally pinned in `_versions.hcl` (currently 0.14.3).

## Consequences

**Positive:**

- Secrets stay in the cloud secret store as the source of truth — no duplication in Git or
  Terraform state
- Declarative sync via ExternalSecret CRDs — secret rotation in the cloud store is automatically
  reflected in Kubernetes (configurable refresh interval)
- Cloud-agnostic model — same ExternalSecret CRDs work with AWS Secrets Manager, Azure Key Vault,
  and GCP Secret Manager by swapping the SecretStore backend
- IRSA provides fine-grained access control — the ESO pod can only read secrets, not write or
  delete them
- Standard Kubernetes Secrets as the output — any workload that consumes K8s Secrets works without
  modification

**Negative:**

- ESO is another operator running in the cluster — adds resource overhead and another component
  to monitor and upgrade
- Secret sync has a refresh interval (default 1 hour) — changes to secrets in the cloud store
  are not instantly reflected in Kubernetes
- The operator has broad read access to the secret store — a compromised ESO pod could read all
  secrets within its IAM policy scope. Mitigated by scoping the IAM policy to specific secret
  paths.
- Current usage is limited — most secrets still flow through Terragrunt `run_cmd` or generated
  data sources rather than ExternalSecret CRDs. The full benefit is realized when workloads adopt
  the CRD-based model.

**Risks:**

- If ESO is down, existing Kubernetes Secrets continue to work (they're already materialized), but
  new secrets won't sync and rotated secrets won't update. Mitigated by monitoring ESO pod health
  and configuring alerts.
- ESO's IRSA role has read access to Secrets Manager. If the IAM policy is too broad, ESO could
  access secrets intended for other services. Mitigated by scoping the policy to the platform's
  secret path prefix.
