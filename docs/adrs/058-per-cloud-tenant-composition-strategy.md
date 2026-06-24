# ADR-058: Per-Cloud Tenant Composition Strategy

**Date:** 2026-06-05

**Status:** Proposed — **strategy/direction** (not implemented). **Vocabulary superseded by
[ADR-067](067-idp-domain-model.md):** the `Tenant`/`XTenant` claim is now `Environment`/`XEnvironment`. **Scope
note:** multi-cloud is deferred — the platform is AWS-only today (Azure/GCP removed), so the per-cloud
Compositions here are forward-looking only. Records *how* the cloud-neutral Tenant API
([ADR-049](049-tenant-model-team-tenant-zone.md), [schema](../architecture/tenant-api-v2.md)) is realized on
more than one cloud. Builds on [ADR-048](048-federated-per-cluster-crossplane.md) (federated per-cluster
Crossplane) and [ADR-047](047-pod-identity-as-aws-identity-standard.md) (Pod Identity = the AWS instance of a
general pattern). AWS is the only realized cloud today; this charts the GCP/Azure path so the implementation
seam is decided before contact with a second cloud.

## Context

The Tenant **claim** is cloud-neutral by construction (ADR-049): a developer never names a cloud, region,
account, or cluster, and the one cloud-specific field (`apps.<app>.permissions`) is explicitly **cloud-keyed**
(`permissions.aws.…`). But the **Composition** that realizes a claim is, today, AWS-only — it renders
`provider-aws` managed resources (IAM Role, EKS Pod Identity association, ECR) inline (delivery-plan A3). So
the coupling to AWS lives entirely in the realization layer, which is where it belongs — but the question of
*how a second cloud plugs in* has not been decided, and the current Composition is monolithic-AWS (the
cloud-neutral and cloud-specific parts share one go-template). Deciding the seam now avoids a painful refactor
later.

## Decision

**One shared XRD/claim; one Composition per cloud; placement selects which.** Concretely:

1. **The XRD (contract) is shared and cloud-neutral.** All clouds expose the same `XTenant` type. No cloud
   forks the API.
2. **Each cloud has its own Composition**, bound to that one XRD. Crossplane supports many Compositions per
   composite type; in the **federated model** (ADR-048) selection is implicit — each cluster installs only its
   own cloud's Composition, so a claim is realized by whatever cluster **placement** routed it to (the Zone's
   `(cloud, region)`, ADR-049). No `compositionSelector` gymnastics in the claim.
3. **Factor the Composition into a neutral core + per-cloud overlays.** The split already exists in the
   realization (A3): the **Kubernetes footprint** (namespace, quota, LimitRange, NetworkPolicies,
   CiliumNetworkPolicies, developer RoleBinding — all `provider-kubernetes`) is **cloud-neutral** and must be
   shared verbatim across clouds; only **workload identity** and **registry** are cloud-specific. The neutral
   core is extracted (a shared template/partial) so GCP/Azure Compositions reuse it rather than duplicate it.

   | concern | AWS (realized) | GCP | Azure |
   | ------- | -------------- | --- | ----- |
   | K8s footprint | provider-kubernetes (**shared**) | shared | shared |
   | workload identity | Pod Identity → IAM Role | Workload Identity → GCP SA | Workload Identity → Managed Identity |
   | per-app grants | `permissions.aws` | `permissions.gcp` | `permissions.azure` |
   | registry | ECR | Artifact Registry | ACR |

4. **Workload identity is one pattern with per-cloud instances.** "Named K8s ServiceAccount → cloud identity"
   is the neutral abstraction; Pod Identity (ADR-047) is the AWS instance, GCP/Azure Workload Identity the
   others. The claim's `serviceAccount` is the neutral binding point; `permissions.<cloud>` (a map, already
   shaped for it) carries the cloud-keyed grants.
5. **Human identity is already cloud-neutral** — Keycloak (ADR-053) brokers app SSO independent of cloud; no
   per-cloud work there.

## Alternatives considered

- **A single mega-Composition that branches on `cloud` inside one template.** Possible, but it grows
  unreadable and couples every cloud's lifecycle into one artifact; the federated model already gives clean
  per-cluster separation. Rejected in favor of per-cloud Compositions sharing a neutral core.
- **A cloud-specific claim per cloud (forked XRDs).** Destroys the portability that is the entire point of the
  neutral API (ADR-049). Rejected.
- **A central multi-cloud control plane reaching into every account/project.** Contradicts the federated
  per-cluster decision (ADR-048) and concentrates blast radius. Rejected.

## Consequences

- The multi-cloud promise becomes "stand up a Zone + write its Composition + route to it," **not** "redesign
  the API" — the neutral claim survives unchanged.
- **Required refactor before a second cloud:** extract the K8s-neutral core from the current AWS Composition so
  it isn't duplicated. Until then the Composition is monolithic-AWS (acceptable while AWS-first).
- **Schema follow-up:** add `permissions.gcp` / `permissions.azure` when those clouds land (the field is a map;
  no breaking change).
- **Deferred** (explicitly): non-AWS **Zone vending** (the GKE/GCP-project or AKS/subscription factory) — the
  one place a cloud-specific provisioning mechanism is justified (ADR-049), behind a cloud-neutral interface;
  and the GCP/Azure Crossplane provider set + their identity/registry overlays.
- Cross-cloud image references differ (registry host per cloud) — surfaced to workloads via the Zone's
  EnvironmentConfig / `status.placement`, not the claim.
