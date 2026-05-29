# ADR-025: Secret Naming Convention and Path Hierarchy

**Date:** 2026-05-24

**Status:** Accepted

## Context

The platform spans 5 AWS accounts (management, platform, preprod, prod, and the organization
root). Secrets currently follow an ad-hoc naming pattern — the Tailscale integration uses
`platform/tailscale/api-key` and `platform/tailscale/oauth`, but nothing formalizes this
convention or requires other services to follow it.

As more services and application teams are onboarded, ad-hoc naming creates three problems:

1. **IAM scoping breaks down.** IRSA policies (ADR-018) use path-based resource ARNs to scope
   secret access. Without a predictable path hierarchy, policies must either enumerate individual
   secret ARNs (brittle) or use broad wildcards (insecure).
2. **Audit review becomes intractable.** CloudTrail logs secret access by ARN. Human-readable,
   hierarchical names make it possible to grep logs by service or team ownership without
   cross-referencing a lookup table.
3. **Secret sprawl.** Without a convention, teams invent their own naming schemes. Flat names
   like `stripe-api-key` provide no organizational context and collide at scale.

SSM Parameter Store also needs a parallel convention for non-secret configuration values (feature
flags, cluster metadata, service discovery endpoints).

### Alternatives Considered

**1. Flat names (e.g., `tailscale-api-key`).** No hierarchy, no IAM scoping capability. Works for
a handful of secrets but provides no organizational structure. Impossible to write IAM policies
that scope access by service or team. Rejected.

**2. Environment-prefixed (e.g., `prod/payments/stripe/api-key`).** Adds an environment tier to
the path. However, each AWS account IS an environment — the platform account only contains
platform secrets, the prod account only contains prod secrets. Adding an environment prefix is
redundant with the account boundary and creates a risk of mismatched labels (a secret named
`prod/...` in the preprod account). Rejected.

**3. Account-ID-prefixed (e.g., `<PLATFORM_ACCOUNT_ID>/tailscale/api-key`).** Technically unique across
accounts, but account IDs are opaque 12-digit numbers that convey no meaning. Anyone reading
the path needs to look up which account the ID maps to. The account boundary already provides
uniqueness. Rejected.

**4. Hierarchical `{owner}/{service}/{secret-name}` (chosen).** The `owner` segment maps to
Kubernetes namespace ownership, creating a natural bridge between the secret store and in-cluster
access patterns. Three levels provide enough structure for IAM scoping without over-nesting.
This formalizes the pattern already in use for Tailscale secrets.

## Decision

Adopt a hierarchical naming convention for AWS Secrets Manager and SSM Parameter Store across
all accounts. The convention uses a maximum of three path segments.

### Secrets Manager

The path format is `{owner}/{service}/{secret-name}`:

- **Owner** maps to the Kubernetes namespace or team that owns the secret
- **Service** identifies the external service or internal component
- **Secret name** identifies the specific credential

Platform account examples:

```text
platform/tailscale/api-key
platform/tailscale/oauth
platform/cloudflare/api-token
platform/argocd/dex-saml-cert
```

Workload account examples:

```text
payments/stripe/api-key
payments/stripe/webhook-secret
backend/database/credentials
frontend/cdn/signing-key
```

Rules:

- No environment prefix — the AWS account boundary IS the environment
- Maximum 3 levels deep (owner/service/name)
- Lowercase, hyphen-delimited segments (no underscores, no camelCase)
- No leading slash (Secrets Manager convention)

### SSM Parameter Store

SSM parameters use a leading slash (AWS convention) and a fixed `config` segment to distinguish
them from secrets:

```text
/{environment}/config/{param-name}
```

Examples:

```text
/platform/config/cluster-domain
/platform/config/vpc-cidr
/preprod/config/feature-flags
```

### IAM Integration

The path hierarchy is the enforcement mechanism for secret isolation. IRSA policies (ADR-018)
scope access using path-based ARN patterns:

- **ESO in platform account:** `arn:aws:secretsmanager:*:${account_id}:secret:platform/*`
- **Per-team IRSA in workload accounts:** `arn:aws:secretsmanager:*:${account_id}:secret:{namespace}/*`

This means a service account in the `payments` namespace can only access secrets under the
`payments/` prefix. Adding a new team's secrets requires no IAM policy changes — the path
convention and wildcard handle it automatically.

### Migration

Two existing secrets already follow the convention (`platform/tailscale/api-key`,
`platform/tailscale/oauth`). No migration is needed for current secrets. New secrets must follow
this convention from the point of adoption.

## Consequences

**Positive:**

- IAM policies use path-based wildcards — adding new secrets under an existing owner requires
  no policy changes
- Human-readable paths make CloudTrail audit logs greppable by owner or service
  (`grep "platform/tailscale"`)
- Maps directly to Kubernetes namespace ownership, creating a consistent mental model from
  secret store to pod
- Formalizes the pattern already in use, so no migration cost for existing secrets
- ESO SecretStore/ClusterSecretStore configurations (ADR-019) can reference predictable paths
  without per-secret enumeration

**Negative:**

- Retroactive renaming is required if the convention changes — Secrets Manager does not support
  renaming, so the old secret must be deleted and a new one created, updating all references
- The 3-level limit may feel constraining for teams with complex service hierarchies (e.g.,
  `payments/stripe/connect/oauth` would violate the convention). Mitigated by using compound
  names in the final segment (`payments/stripe/connect-oauth`)

**Risks:**

- Teams creating secrets outside the convention, either through the console or automation that
  doesn't enforce naming rules. Mitigated by CloudTrail monitoring for `CreateSecret` events
  with non-conforming names, and by documenting the convention in onboarding materials.
- Path-based IAM wildcards mean a compromised pod with IRSA access to `payments/*` can read
  ALL payment secrets, not just its own service's secrets. This is an acceptable trade-off at
  current scale — per-service scoping (e.g., `payments/stripe/*`) can be introduced later if
  the threat model requires it.
