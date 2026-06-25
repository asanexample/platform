# ADR-081: Platform-Owned Internal Service Delivery — a GitOps Paved Road for Internally-Developed Services and Agents

**Status:** Proposed (2026-06-24)

## Context

The platform has two delivery worlds, and only one is paved.

**Tenant apps** ride a rich, standardized, GitOps-native paved road: a `Product` registry + an `XEnvironment` claim
([ADR-067](067-idp-domain-model.md)/[ADR-069](069-delivery-source-of-truth-product-environment.md))
→ a per-Product `ApplicationSet` → a `Release`-carried image digest injected by `templatePatch`
([ADR-071](071-digest-promotion-via-control-plane.md)) → signed CI ([ADR-050](050-shared-build-sign-reusable-workflow.md)). Adding a
tenant service is a registry edit. But that road is **tenant-scoped by construction** — team/product nesting, the
Crossplane Environment Composition, the Kyverno envelope, quotas.

**Platform-owned, internally-developed services** have **no paved road at all.** Backstage and the self-hosted ARC
runner are each bespoke Terragrunt-Helm modules; each invented its own delivery, pins its image manually in Helm values,
and is invisible to ArgoCD (no drift detection, no self-heal, no sync status). They are one-offs.

[ADR-074](074-agentic-workloads-platform.md) makes agents a first-class workload class and anticipates running *many* of them; the
triage copilot ([ADR-080](080-triage-copilot.md)) is the first. Graduating it the bespoke way would make it a **third**
one-off — and the fourth, fifth, and Nth agents would each be hand-rolled too. The gap is real: there is no standardized,
GitOps-native way to deploy an internally-developed, platform-owned service or agent.

## Decision

Define a **thin, GitOps-native paved road for platform-owned internal services** (including agents), by **reusing the
existing ArgoCD / ApplicationSet / promotion machinery platform-scoped** — not by inventing a new substrate. A platform
service becomes a one-line registry entry plus a small set of supply-chain conventions. **The triage copilot is the
reference implementation.**

## Design

### D1 — Registry: `gitops/platform-services/<name>.yaml`

A flat registry (no team/product nesting), one file per service, `kind: PlatformService`, owner = platform. Static spec
only — repo, the in-repo deploy path, the target namespace:

```yaml
apiVersion: platform.refplat.org/v1beta1
kind: PlatformService
metadata:
  name: triage-copilot
spec:
  repo: asanexample/triage-copilot
  path: deploy           # Kustomize app in the service repo
  namespace: triage-copilot
```

### D2 — Delivery: a platform-services `ApplicationSet`, cloned from the per-Product one

The `argocd-apps` module reads `gitops/platform-services/` at Terragrunt time (the same `fileset` pattern it uses for
`gitops/products/`) and emits, per service, a near-copy of the per-Product `ApplicationSet`: a **git-files generator**
over `gitops/releases/platform/<name>/*.yaml` (via the `applicationset-raw` chart), an Application whose **source** is the
service repo's `deploy/` (Kustomize) and whose **destination** is the platform cluster + `spec.namespace`, with
`automated { selfHeal, prune }`. A per-service `AppProject` scopes it to that namespace and those two repos.

### D3 — Image pinning: reuse the `Release` digest + `templatePatch` (ADR-071)

Unchanged from the tenant flow: a static registry file (D1) plus a churning `gitops/releases/platform/<name>.yaml`
carrying the built digest, CI-bumped through the existing promote App / gitops Gate. The ApplicationSet's `templatePatch`
overlays it as a Kustomize image override. No rebuild-to-deploy; the exact signed digest is what ships.

### D4 — Supply-chain + identity conventions (part of the standard)

Every platform service: its **own repo**; a **signed image** at `platform/<svc>` (a dedicated `github-actions-ecr-push-<svc>`
OIDC role, cosign keyless + SBOM — the backstage/gha-runner pattern, [ADR-050](050-shared-build-sign-reusable-workflow.md) posture); a
**least-privilege Pod Identity** unit ([ADR-047](047-pod-identity-as-aws-identity-standard.md)); and **read-only RBAC** scoped to what it reads.
The triage-copilot's already-merged pieces instantiate this (its Pod Identity unit; its ECR repo + OIDC role; its RBAC).

### D5 — Repo credentials: reuse the org-wide ArgoCD PAT

ArgoCD already holds an org-wide `repo-creds` Secret for `https://github.com/asanexample` (a PAT from Secrets Manager).
Any new `asanexample/*` service repo is authenticated automatically — **no per-service credential.**

### D6 — Deliberately not tenant-shaped

Platform services are **trusted infrastructure**, not tenants, so this road omits the tenant guardrails by design: **no**
Crossplane/`XEnvironment`, **no** Kyverno team-envelope or quota, **no** team/product nesting, and **no** promotion
ladder (single target = the platform cluster; a preprod target is a future option). The trust boundary is platform
ownership + code review + the gitops Gate, not the per-tenant admission envelope.

### D7 — Relationship to a declarative `PlatformService`/`Agent` CRD (ADR-074)

This paved road is the **substrate**, not the ceiling. A future declarative `Agent`/`PlatformService` CRD (the ADR-074
hypothesis) would *compile down to* a registry entry + these conventions, exactly as `XEnvironment` compiles down to a
per-Product ApplicationSet today. Building the substrate first does not foreclose the CRD; it earns it.

## Scope

- **In:** the `gitops/platform-services` registry, the platform-services ApplicationSet in `argocd-apps`, the D4 supply-chain
  conventions, and the triage copilot as the reference implementation.
- **Out (for now):** migrating backstage / gha-runner onto the road (opt-in, later); the declarative CRD (D7); a preprod /
  multi-cluster target; any change to the tenant paved road.

## Consequences

- Onboarding a platform service/agent becomes a **registry edit**, with GitOps visibility, drift detection, and self-heal —
  and it sets the template for the ADR-074 agent fleet.
- **Two delivery worlds persist** until backstage/gha-runner migrate. Accepted: migration is opt-in and out of scope here.
- Platform services **bypass the tenant guardrails by design** — the safety story rests on platform ownership + review, which
  is appropriate for trusted infra but must stay an explicit, conscious boundary.
- The reused machinery (per-Product ApplicationSet, promote App, `templatePatch`) now has a second consumer, so changes to it
  must consider both tenants and platform services.

## Alternatives considered

- **Standardize the Terragrunt-Helm one-off** (a shared chart skeleton + conventions, matching backstage). Lighter and proven,
  but not GitOps-native (no drift/self-heal/visibility) and it cements two delivery worlds permanently. Rejected for a
  GitOps-first platform.
- **Go straight to a declarative `PlatformService`/`Agent` CRD.** The eventual north star (D7), but the heaviest option and
  premature before the substrate is proven. Deferred.
- **Reuse the tenant paved road as-is.** Forces platform services through the team/product/Crossplane/Kyverno envelope they do
  not fit, and conflates trusted infra with tenant workloads. Rejected.

## Related

- [ADR-067](067-idp-domain-model.md) / [ADR-069](069-delivery-source-of-truth-product-environment.md) — the
  tenant delivery source-of-truth this mirrors.
- [ADR-071](071-digest-promotion-via-control-plane.md) — the digest-promotion / `templatePatch` flow reused for D3.
- [ADR-074](074-agentic-workloads-platform.md) — agents as a first-class workload class; D7's future CRD.
- [ADR-080](080-triage-copilot.md) — the triage copilot, this road's reference implementation.
- [ADR-047](047-pod-identity-as-aws-identity-standard.md) — Pod Identity (D4). [ADR-050](050-shared-build-sign-reusable-workflow.md) — signed CI posture (D4).
