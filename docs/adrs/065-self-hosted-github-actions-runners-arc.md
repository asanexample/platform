# ADR-065: Self-Hosted GitHub Actions Runners (ARC) on the Platform Cluster

**Date:** 2026-06-10

**Status:** Proposed

## Context

Terragrunt applies currently run from an operator's local checkout. This is convenient at the
current scale but has three structural problems we want to retire as the platform matures toward
fully-automated, GitOps-driven operations:

1. **Stale-local-state failures.** A `terragrunt apply` from a local checkout that is behind `main`
   silently no-ops the merged-but-unpulled change (the #305 New Team failure: keycloak-config
   reported "0 added, 0 changed" against a stale local `main`). CI always applies from the merged
   SHA; this entire failure class disappears.
2. **Human-in-the-loop convergence.** After an onboarding PR merges, the git-native `Team` CR
   converges via ArgoCD automatically, but the Terragrunt-managed consumers (Keycloak groups/roles,
   ArgoCD RBAC) wait for a human to run applies (ADR-053, ADR-062/063). We want apply-on-merge.
3. **No audit-grade apply trail.** A local apply is attributable only by convention. A CI apply is
   tied to a merge commit, a workflow run, and an OIDC identity.

The blocker is **network reachability**, not credentials. The estate splits in two:

- **AWS-only units** (networking, iam-roles, eks control-plane, ecr, organizations, route53,
  cloudtrail, github-oidc, …) talk only to AWS APIs. GitHub-hosted runners already handle these via
  OIDC federation (ADR-036) — `build.yml` pushes to ECR and Terratest assumes roles this way today.
  These need **no** self-hosted runner.
- **Cluster-facing units** (argocd, cilium, eks-addons, crossplane, tenant-claims, policy,
  keycloak/keycloak-config, gateway, cert-manager, external-dns/secrets, backstage, …) use the Helm
  and Kubernetes providers and must reach the **private EKS API endpoint** (ADR-010). GitHub-hosted
  runners cannot — they have no VPC connectivity. `keycloak-config` is the extreme case: it configures
  Keycloak over an in-cluster `kubectl` port-forward (`scripts/kc-portforward.sh`, ADR-059), so it must
  run *inside* the cluster network, not merely reach the API.

This is the same private-API access problem ADR-010 names and ADR-021 sidesteps for *application*
delivery (ArgoCD runs in-cluster and pulls from git). Application delivery is solved. **Infrastructure
apply from CI is not** — and unlike app manifests, Terragrunt apply is push-based by nature (it runs a
binary that drives the providers), so the GitOps-pull escape hatch doesn't apply to it.

Both ADR-010 and ADR-036 already name "self-hosted runners on EKS" as the intended future solution;
this ADR makes that decision concrete.

### Alternatives Considered

**1. GitHub-hosted runners + a tunnel (Tailscale or SSM) into the VPC.** Reuse the developer access
path (ADR-011 Tailscale operator, or the SSM bastion) from a hosted runner: bring up the tunnel,
apply, tear it down. No new long-lived infrastructure. Rejected as the primary path: it is fragile in
CI (tunnel bring-up/teardown per job, auth state, flakiness), it puts an ephemeral hosted runner —
outside our trust boundary — temporarily inside the VPC on every apply, and it does **not** cleanly
solve the in-cluster `kubectl` port-forward case (keycloak-config). It is a reasonable *break-glass*
or interim mechanism, not the production design.

**2. Re-open the EKS API to public (allowlisted) access for CI.** Let hosted runners hit a public
endpoint restricted to GitHub's egress ranges. Rejected: GitHub's runner egress is broad and changes,
so the allowlist is effectively the internet; and it directly contradicts the private-endpoint
lockdown posture (ADR-010). A temporary public window post-lockdown is not acceptable.

**3. Self-hosted runners on a standalone EC2 Auto Scaling group.** Runners on EC2 in the VPC with an
instance profile. Solves reachability and keeps credentials in AWS. Rejected in favor of ARC because
it reintroduces VM lifecycle management (AMIs, patching, scaling, registration) that we have
deliberately moved onto Kubernetes everywhere else, and it does not give us ephemeral
one-job-per-pod isolation as cleanly.

**4. Actions Runner Controller (ARC) on the platform EKS cluster (chosen).** ARC is the Kubernetes-
native runner autoscaler: a controller manages **runner scale sets** that register with GitHub and
spin up **ephemeral, one-job-per-pod** runners on demand. It is deployed by **Terragrunt
(`helm_release`)** like every other platform add-on (backstage, crossplane, cert-manager,
external-secrets) — *not* via ArgoCD, which on this platform is reserved for tenant workloads (app
repos, Team CRs, XTenant claims), not control-plane infrastructure. It runs inside the VPC with native
reach to the platform API, scales to zero when idle, and gives each job a fresh pod with no persisted
state. This matches the platform's existing operational model (Terragrunt-delivered Helm release,
K8s-native, ephemeral) better than any alternative.

### Where to host: platform cluster vs. per-cluster runner sets

The platform cluster is the **shared-services** cluster — it already hosts ArgoCD, the transit-gateway
hub, and the private API, and it is the control point for the rest of the estate. ARC belongs there.
But a runner *on the platform cluster* reaches the *platform* API natively and the *preprod* API only
across the **transit gateway** (the hub is in the platform account; preprod is a spoke, ADR — TGW +
cross-vpc-dns are already deployed). That cross-VPC path requires preprod's API access configuration
to admit the runner's source. Two viable shapes:

- **(A) One runner pool on the platform cluster, cross-VPC to spokes over the TGW.** Fewest moving
  parts; one ARC install. Requires each spoke's private API to allow the platform VPC CIDR (or the
  runner subnet) and the cross-VPC-DNS resolution that already exists for operator access.
- **(B) A runner scale set per workload cluster.** Each cluster runs its own runners with native
  in-cluster reach (and native port-forward for keycloak-config). Cleaner blast-radius isolation and
  no cross-VPC API exposure, at the cost of N ARC installs and per-cluster GitHub registration.

We start with **(A)** for the platform cluster's own units and the access-model convergence in #305
(which targets platform-cluster units: keycloak-config, argocd, argocd-apps), and adopt **(B)**'s
per-cluster runner set for a workload cluster when we extend apply-on-merge to that cluster's
cluster-facing units (notably so keycloak-config-style in-cluster port-forwards run locally). This is
recorded as a follow-up, not built up front.

## Decision

Adopt **Actions Runner Controller (ARC)** as the self-hosted runner platform, deployed to the
**platform EKS cluster via ArgoCD**, to give CI workflows in-VPC reachability for Terragrunt applies
of cluster-facing units (and any other in-cluster CI work). GitHub-hosted runners + OIDC remain the
path for AWS-only units and for non-cluster CI (lint, validate, build/sign).

Concretely:

1. **ARC controller + runner scale sets**, packaged as a shared module under `infra/modules/` and
   deployed by **Terragrunt (`helm_release`)** — the same delivery path as backstage, crossplane, and
   cert-manager. ArgoCD is *not* used here; on this platform it delivers tenant workloads, not the
   control plane. Because ARC is precisely what lets CI manage the cluster, the
   `actions-runner-controller` unit is itself the **one cluster-facing unit that stays on local apply /
   `platctl` (break-glass)** — it cannot bootstrap itself; every other cluster-facing unit graduates to
   CI behind it. Runners are **ephemeral** (one job per pod, no reuse) and **scale to zero** when idle.
   Registration is **repo-level** (the `platform` repo) for the privileged infra-apply pool — the
   tightest trust surface; broader scopes (org-level, app CI) are added later as separate pools.
2. **Runner identity via Pod Identity, not stored secrets.** Runner pods get AWS access through EKS
   Pod Identity (ADR-047) bound to a **dedicated, narrowly-scoped CI ServiceAccount** — not the app
   pods' identities, not a node role. For Terragrunt applies, that identity is trusted to assume
   **`PlatformDeployer`** (the existing deployer role, per root.hcl), gated by a trust condition
   scoped to this purpose — a **separate trust path from the app-repo ECR-push roles** (ADR-036);
   never the app-push role.
3. **GitHub registration via a GitHub App**, least-privileged to the runner scope, with the App
   credentials in Secrets Manager and surfaced via External Secrets (consistent with how Backstage's
   GitHub Apps are handled) — not a long-lived PAT.
4. **Separate runner pools for infra-apply vs. app/CI work.** A runner that can assume `PlatformDeployer`
   and reach the cluster API is a high-value target; it must not be the same pool that runs untrusted
   app build steps. Distinct scale sets, distinct ServiceAccounts/identities, distinct labels.
5. **Apply-on-merge runs from the merge commit only**, never a PR ref, preserving the CI-gate-integrity
   posture of ADR-062 §4, with a serializing concurrency group against the Terragrunt state lock.
6. **`platctl` (local apply / bootstrap) is retained as break-glass.** Because the runners live on the
   platform cluster, a bad apply that degrades the cluster can also degrade the runners that would fix
   it (the ADR-011 "cluster down → access down → SSM fallback" failure mode). The local apply path and
   `platctl bootstrap` must remain fully functional for recovery and initial bring-up. Concretely:
   because ARC is itself Terragrunt-deployed, the `actions-runner-controller` unit is applied **locally**
   (it cannot bootstrap itself) — it is the permanent floor of the local-apply path, and the bootstrap
   ordering must bring it up before any CI-driven apply can run.

This ADR decides the **mechanism** (ARC on the platform cluster) and its security shape. The **rollout**
— which units move to apply-on-merge, and in what order — is owned by #305 (Phase 1: post-merge
converge of the access-model units) and its Phase 2 follow-up (general plan-on-PR / apply-on-merge).
The current human-gated apply stance documented in `infra/docs/14-deployment-workflows.md` is
superseded incrementally as those phases land, not in one cut-over.

## Consequences

### Positive

- **Cluster-facing units become CI-applyable.** The Helm/Kubernetes-provider units (and the
  keycloak-config port-forward case under per-cluster runners) can run from CI, which they cannot on
  hosted runners. This unblocks #305 and the broader apply-on-merge goal.
- **Stale-local-state failures are eliminated** for any unit moved to CI — applies always run from the
  merged SHA.
- **Ephemeral, isolated jobs.** One pod per job, scale-to-zero, no persisted runner state — a strong
  default against cross-job contamination and idle cost.
- **No stored AWS credentials.** Runner AWS access is Pod Identity → assume-role, short-lived and
  auditable in CloudTrail (consistent with ADR-036/047), rather than keys on a VM.
- **Consistent operational model.** ARC is a Terragrunt-deployed Helm release and K8s-native like every
  other platform add-on; no new VM fleet to patch or scale.
- **Audit-grade apply trail.** Every CI apply ties to a merge commit, a workflow run, and an OIDC/Pod
  Identity principal.

### Negative

- **The runners are now critical infrastructure with a bootstrap chicken-and-egg.** CI that manages the
  platform cluster runs *on* the platform cluster. A bad apply can take down the runners that would
  remediate it. Mitigated by retaining `platctl`/local apply as break-glass (decision point 6) and by
  keeping the bootstrap path local-capable.
- **A high-value credential now lives in the cluster.** A runner pool trusted to assume `PlatformDeployer`
  and reach the API is a prime escalation target. Mitigated by pool separation (infra vs. app),
  ephemeral pods, narrowly-scoped Pod Identity, merge-commit-only applies, and the ADR-062 §4 CI-gate
  integrity controls. This concentration of privilege must be reviewed as part of the threat model.
- **Cross-VPC API exposure (shape A).** Running platform-hosted runners against spoke (preprod) APIs
  requires opening each spoke's private API to the platform VPC over the TGW — a deliberate widening of
  the private-endpoint surface. Shape B (per-cluster runners) avoids this but multiplies the ARC
  footprint; the choice is per-cluster and explicit.
- **New operational surface.** ARC itself (controller, scale sets, the GitHub App, the listener) is
  software we now run and must upgrade, monitor, and secure — the very overhead ADR-036 chose OIDC to
  avoid. Justified now because the reachability requirement (private API) leaves no equivalent-security
  alternative for cluster-facing applies; it was not justified when only AWS-only access was needed.
- **Idle latency / cold starts.** Scale-to-zero means the first job after idle waits for a runner pod to
  schedule and register. Acceptable for infra applies; tunable with a warm-pool minimum if needed.

## References

- ADR-010 (private-only EKS API endpoint — the reachability problem)
- ADR-011 (Tailscale for private cluster access — the developer path and the "cluster down → access
  down" failure mode)
- ADR-021 (ArgoCD for GitOps delivery — how this is deployed, and why app delivery already sidesteps
  the private API)
- ADR-036 (GitHub Actions OIDC federation — the AWS-only path that stays; the separate deployer trust)
- ADR-047 (Pod Identity as the AWS identity standard — runner AWS access)
- ADR-062 §4 (CI-gate integrity — merge-commit-only applies)
- #305 (Terragrunt in CI: post-merge converge for the access-model units — the rollout this enables)
