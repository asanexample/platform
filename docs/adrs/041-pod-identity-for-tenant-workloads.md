# ADR-041: EKS Pod Identity for Tenant Workloads

**Date:** 2026-05-30

**Status:** Accepted — narrows [ADR-018](018-irsa-for-pod-identity.md) for tenant workloads.

## Context

[ADR-018](018-irsa-for-pod-identity.md) chose **IRSA** for pod-level AWS access on EKS and explicitly
rejected EKS Pod Identity, citing the extra Pod Identity Agent DaemonSet and its BYOCNI ordering
dependency. That decision stands for **platform add-ons** (argocd, cert-manager, external-dns,
external-secrets, the Kyverno-ECR role) — they are few, platform-owned, and already wired for IRSA.

**Tenant** workloads are a different problem. Until now they had *no* AWS access at all: the Kyverno
policy `disallow-irsa-annotation-cross-team` blanket-denies any tenant ServiceAccount carrying an
`eks.amazonaws.com/role-arn` annotation (the IRSA mechanism), because an unrestricted IRSA annotation in
a tenant namespace is a cross-team privilege-escalation vector. The missing capability — "team identity →
least-privilege, **isolated** AWS access" — is the last piece of the tenant-isolation story (alongside
per-team ECR push, image signing, route-hostname guards, namespaces, and quotas).

IRSA is a poor fit for *tenants* specifically:

- It needs **per-tenant OIDC trust-policy boilerplate** (`sub` = `system:serviceaccount:team-<t>:<sa>`),
  which scales badly and puts IAM trust authorship close to tenant config.
- It reuses the **default Kubernetes API ServiceAccount token** (audience `sts.amazonaws.com`), which
  collides with the platform's hardening: tenant pods set `automountServiceAccountToken: false`
  (enforced by Kyverno). Under IRSA, turning the SA token off breaks credential delivery.

## Decision

Use **EKS Pod Identity** for **tenant** workload AWS access. Platform add-ons keep IRSA (ADR-018
unchanged for them).

A platform-managed **`aws_eks_pod_identity_association`** binds `(cluster, namespace, serviceAccount) →
IAM role`. Pods running as that named ServiceAccount receive the role's credentials from the Pod Identity
Agent — **no SA annotation**. Per-team config is declared in `teams.hcl` (`aws` block); the modules stay
team-agnostic.

Why this fits tenants where IRSA didn't:

- **Isolation is platform-controlled and AWS-API-gated.** Creating an association requires
  `eks:CreatePodIdentityAssociation` (an AWS API call); tenants have only namespace-scoped Kubernetes
  RBAC, so they **cannot self-grant**. The association is intrinsically scoped to one `(namespace, SA)`.
- **No per-tenant trust boilerplate.** The role trusts the `pods.eks.amazonaws.com` service principal
  (scoped to our account via `aws:SourceAccount`); the *association* is the binding, not a bespoke OIDC
  `sub` condition.
- **Compatible with `automountServiceAccountToken: false`.** Pod Identity injects its **own** projected
  token (`eks-pod-identity-token`) + `AWS_CONTAINER_CREDENTIALS_FULL_URI` via the pod-identity webhook,
  independent of the default SA token. (This is the concrete reason IRSA was unworkable for tenants.)

### Isolation model — default-deny, by construction

A team gets **zero** access to a bucket it didn't declare. Two independent locks, and cross-account
access requires **both**:

1. **Identity policy** on `Pod-team-<team>` — generated only from that team's own `aws.s3` block, with
   the **exact bucket ARN** as resource (no wildcard).
2. **Resource policy** on the bucket — grants only that team's role ARN; public access fully blocked.

Both the bucket **name** and its **sole reader** are derived from the owning team key
(`<org>-team-<team>-<suffix>` → `Pod-team-<team>`), so a bucket named for team X can only ever grant
`Pod-team-X` — a cross-grant is structurally impossible, not merely caught in review. This mirrors the
per-team ECR scoping (`team-<team>/*`). Genuinely shared buckets would be a deliberate future opt-in.

Defense in depth: the tenant egress NetworkPolicy blocks IMDS (`169.254.169.254`), so a tenant cannot
steal the broader **node** role; it still reaches the Pod Identity agent (`169.254.170.23`) and S3.

### Components

- **Module** `iam_roles` extended to support `service` trust principals + `trust_actions`
  (`sts:AssumeRole`, `sts:TagSession`).
- **New modules** `eks-pod-identity` (associations) and `s3` (private/encrypted buckets + scoped
  cross-account policy).
- **Units** `eks-addons` (adds `eks-pod-identity-agent`), `iam-roles` (generates `Pod-team-<team>`),
  new `pod-identity` (preprod, associations), new `s3-shared` (platform account, cross-account buckets).
- **Kyverno** `disallow-irsa-annotation-cross-team` stays a **deny** — tenants never need the annotation,
  so it remains a backstop. No new policy: associations are AWS-side objects Kyverno can't see and
  tenants can't create.

## Consequences

- Tenants get least-privilege, isolated AWS access with no annotation and no per-tenant trust authoring.
- One more cluster-wide DaemonSet (the Pod Identity Agent) on tenant clusters — the cost ADR-018 weighed,
  now justified by real tenant need. Deployed via `eks-addons` after Cilium + nodes (BYOCNI ordering).
- Apps must use a **named** ServiceAccount (never `default`) and set `serviceAccountName`.
- IRSA and Pod Identity now coexist: IRSA for platform add-ons, Pod Identity for tenants. Documented so
  the two mechanisms aren't confused.

See the runbook [`tenant-aws-access-pod-identity.md`](../runbooks/tenant-aws-access-pod-identity.md) for
how a team requests access and the cross-team isolation test.
