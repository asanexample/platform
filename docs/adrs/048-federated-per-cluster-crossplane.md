# ADR-048: Federated, Per-Cluster Crossplane for Tenant Provisioning

**Date:** 2026-06-02

**Status:** Accepted — **implemented (#174); migration complete.** The federated Composition is live on
preprod and both teams (alpha, bravo) are provisioned by `Tenant` claims; the legacy Terragrunt tenant units
(`tenants`, `pod-identity`, and the platform `s3-shared` unit) and the `infra/modules/tenant` module are
retired. Refines [ADR-046](046-back-stack-for-developer-self-service.md). ADR-046 adopted Crossplane as the
tenant control plane and described it running on the platform (hub) cluster. This ADR sets the **topology**:
Crossplane runs on **each workload cluster** and provisions that cluster's tenants locally, rather than a
single hub reaching across clusters. The rest of ADR-046 is unchanged.

> **Vocabulary superseded by [ADR-067](067-idp-domain-model.md):** "Tenant"/`Tenant` claim → **Environment**/`XEnvironment` (Team→Product→Service; the intermediate `XTenant` was also removed); `teams.hcl` → the git-native `Team` + `Product` registries. The decision/topology below is unchanged — read the tenant vocabulary as the v2 naming.

## Context

Tenants run on workload clusters (preprod today, prod later), **not** on the platform (hub) cluster — the
hub hosts shared services (ArgoCD, observability, the registry). So "Crossplane provisions tenants" raises a
topology question ADR-046 did not settle: does **one** Crossplane on the hub reach *into* each workload
cluster, or does **each** workload cluster run its own Crossplane?

A tenant's footprint, mapped in full, is almost entirely **local to the workload cluster**:

- **Kubernetes** — namespace, ResourceQuota, LimitRange, NetworkPolicies, CiliumNetworkPolicies, the
  developer RoleBinding, and the per-team Kyverno `ClusterPolicy`s — all live on the tenant's cluster.
- **AWS** — the `Pod-team-<team>` IAM role and its EKS Pod Identity association are in the tenant cluster's
  **own account**.
- The **only** cross-account resource is the **ECR repository** (`team-<team>/<app>`), which lives in the
  platform account and is pulled cross-account. (The S3 cross-account demo is illustrative, not core.)

A hub topology would therefore force the hard parts — cross-cluster `provider-kubernetes` authentication to
every workload cluster (token rotation, remote RBAC, network path) and a provisioning identity able to write
to **every** cluster and **every** account — to handle resources that are otherwise local. It also makes the
hub a single point of failure for all tenant provisioning.

## Decision

**Run Crossplane on each workload cluster, federated.** Each cluster's Crossplane provisions its own
tenants:

- **`provider-kubernetes` is in-cluster** (`InjectedIdentity`) — no cross-cluster auth at all.
- **`provider-aws` uses the cluster's own-account Pod Identity** (ADR-041/047) for the IAM role + Pod
  Identity association.
- **ECR — the one cross-account resource — uses a single `assumeRoleChain` ProviderConfig** into a scoped
  platform-account role.
- The **provisioning identity is scoped to one cluster + one account**, with a permissions boundary on the
  roles it creates — a far smaller blast radius than a hub identity with org-wide reach.

The platform (hub) cluster keeps its Crossplane (installed in P1) as a standard add-on; it does not provision
other clusters' tenants. The `Tenant` XRD + Composition are deployed to each workload cluster as a Terragrunt
add-on unit — the same per-cluster pattern as `policy`, `cilium`, `cert-manager`, and every other add-on.

> **Note (2026-06-25, [ADR-082](082-platform-agent-runtime-xagent.md)).** The hub's Crossplane gains an **`XAgent`**
> XRD + Composition to provision **platform agents** (hub-local platform infrastructure). This is consistent with this
> ADR: it is a *different* Composition from the tenant one, provisions **hub-local, in-cluster** resources via
> `InjectedIdentity` provider-kubernetes (no cross-cluster reach, no remote provider creds, not a provisioning SPOF for
> other clusters), and does **not** provision tenants. Tenants still run only on workload clusters; the hub still hosts
> platform infra — agents are simply more of it.

**Tenant claims are delivered by GitOps**, not submitted to a central API: Backstage (or a platform engineer)
writes a `Tenant` claim into a platform-controlled git path; ArgoCD syncs it to the target cluster; that
cluster's local Crossplane reconciles it. Centralized *visibility* (all claims in git) without centralized
*reach*.

## Alternatives considered

**1. Hub Crossplane on the platform cluster (ADR-046's original phrasing) (rejected).** One control plane to
operate and a single place to see all claims. But it requires cross-cluster `provider-kubernetes` to every
workload cluster (the most fragile component), a provisioning identity with write access to every
cluster/account, and it makes the hub a provisioning SPOF — all to manage resources that are local to the
tenant cluster. GitOps-delivered claims already give the "single view" benefit without the central reach.

**2. Hybrid — hub API, delegated execution (rejected).** A hub that accepts claims and delegates to
per-cluster engines. More moving parts than per-cluster with no advantage once claims are GitOps-delivered.

## Consequences

**Positive.** No cross-cluster Kubernetes auth; least-privilege per-cluster/per-account provisioning
identities; each cluster is self-contained (consistent with the independent-cluster, airgapped-capable
network model); the topology matches every other add-on, so operating it is the established per-cluster
pattern; clean GitOps claim flow toward Backstage.

**Negative / trade-offs.**

- **N Crossplane installs** to run and upgrade rather than one — but they are identical Terragrunt units
  (a version bump applied per cluster), and the platform already operates N copies of every add-on.
- **The XRD + Composition must be deployed to each cluster** (GitOps/Terragrunt) — version skew across
  clusters is possible and must be managed like any other add-on version.
- **ECR remains cross-account**, handled by one `assumeRoleChain` ProviderConfig + a scoped platform-account
  role (the lone cross-account seam).
- **Backstage (P4) routes claims via git/ArgoCD to the target cluster** rather than calling one API — which
  is the desired GitOps posture anyway.
