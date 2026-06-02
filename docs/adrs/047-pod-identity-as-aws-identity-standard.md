# ADR-047: EKS Pod Identity as the Standard for Pod AWS Identity

**Date:** 2026-06-02

**Status:** Accepted — supersedes [ADR-018](018-irsa-for-pod-identity.md)'s rejection of Pod Identity and
broadens [ADR-041](041-pod-identity-for-tenant-workloads.md) from *tenant* workloads to **all** pod-level
AWS access. Go-forward standard; the existing IRSA platform add-ons migrate during the planned stack
rebuild, not in place.

## Context

How a pod on EKS gets AWS credentials has been decided twice:

- **[ADR-018](018-irsa-for-pod-identity.md)** chose **IRSA** (IAM Roles for Service Accounts, OIDC-federated)
  for all pod-level AWS access and **explicitly rejected EKS Pod Identity**, citing the extra Pod Identity
  Agent DaemonSet and its BYOCNI ordering dependency on the cluster.
- **[ADR-041](041-pod-identity-for-tenant-workloads.md)** narrowed that: **Pod Identity for tenant
  workloads** (the association is a platform-controlled, AWS-API-gated isolation boundary; no per-tenant
  OIDC trust boilerplate; and it works with `automountServiceAccountToken: false`, which IRSA cannot). It
  left **platform add-ons on IRSA** — argocd, cert-manager, external-dns, external-secrets, the
  Kyverno-ECR role — on the grounds that they are few, already wired, and not worth churning.

Two things have since changed that undercut the original split:

1. **The Pod Identity Agent objection is moot.** The agent now runs on **both** clusters — preprod (for
   tenants, ADR-041) and the platform cluster as of [ADR-046](046-back-stack-for-developer-self-service.md)
   (Crossplane's AWS provider authenticates via Pod Identity). We already pay the DaemonSet cost
   everywhere, so ADR-018's reason to avoid Pod Identity no longer applies.
2. **A full stack rebuild is planned.** Pod Identity roles trust the `pods.eks.amazonaws.com` service
   principal (scoped by `aws:SourceAccount`), **not** a per-cluster OIDC provider — so they survive a
   cluster rebuild without re-authoring trust policies. IRSA roles are pinned to a specific cluster's OIDC
   issuer and must be re-wired on every rebuild.

The result today is a mixed, undocumented state: platform add-ons on IRSA, tenants and Crossplane on Pod
Identity. This ADR makes the direction intentional.

## Decision

Adopt **EKS Pod Identity as the standard for all pod-level AWS access** — platform components and tenant
workloads alike. Specifically:

- **New components use Pod Identity.** Crossplane (ADR-046) already does and is the first platform
  component on the standard; it is the reference, not drift to undo.
- **Existing IRSA platform add-ons migrate at the rebuild, not in place.** argocd, cert-manager,
  external-dns, external-secrets, the aws-ebs-csi-driver IRSA role, and the Kyverno-ECR role keep working
  on IRSA until the planned rebuild, which is the clean place to cut them over (each: drop the OIDC-trust +
  SA annotation, add an `aws_eks_pod_identity_association`). A big-bang in-place migration of working
  controllers buys little now and would be redone by the rebuild.
- **Every cluster runs the `eks-pod-identity-agent` addon.** Already true for preprod and the platform
  cluster; it becomes a standing requirement for any new cluster.
- **The tenant IRSA-annotation ban stays.** The Kyverno `disallow-irsa-annotation-cross-team` policy that
  denies any `eks.amazonaws.com/role-arn` annotation in a `team-*` namespace is a **security control**, not
  a mechanism preference — it prevents cross-team privilege escalation regardless of which credential
  mechanism the platform uses, and is unaffected by this decision.

## Alternatives considered

**1. Migrate every platform add-on to Pod Identity now (rejected).** Removes the mixed state immediately,
but churns working controllers for no functional gain and redoes work the rebuild will redo anyway. Higher
risk, poor timing.

**2. Keep the ADR-041 split and revert Crossplane to IRSA (rejected).** Restores consistency the other way
and is low-effort, but keeps two credential mechanisms indefinitely and forfeits the cluster-portability
win that matters most for the rebuild. It also re-adopts the IRSA boilerplate ADR-041 already found
inferior.

**3. Leave the mixed state undocumented (rejected).** The status quo works, but an unexplained split reads
as drift and invites inconsistent choices on the next component.

## Consequences

**Positive.** One credential model to reason about, document, and operate; no per-component OIDC
trust-policy authoring; roles are **cluster-portable** (survive the rebuild without re-wiring trust); the
direction is now explicit, so new components have a clear default.

**Negative / trade-offs.**

- **An interim coexistence window** — IRSA add-ons and Pod Identity components run side by side until the
  rebuild. Both work; the only cost is that two mechanisms are live for a while.
- **The agent is now a hard per-cluster dependency** (already the reality). A cluster without it silently
  breaks AWS credential delivery for every workload.
- **Migration is deferred, not free** — the rebuild must actually carry the cutover; tracked as rebuild
  scope so it is not lost.
- **A Cilium/overlay nuance applies to controllers that serve webhooks** (e.g. Crossplane runs hostNetwork
  so the EKS control plane can reach its conversion webhook). That is orthogonal to the credential
  mechanism but worth remembering when moving a webhook-serving controller onto any cluster.
