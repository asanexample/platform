# Grants — `AccessGrant` (human) + `ServiceGrant` (network)

This directory holds two DIFFERENT grant kinds, both synced to the cluster by the same **`grants`
registry-sync** ArgoCD app (see `infra/modules/argocd-apps/delivery.tf` — both kinds are
cluster-resource-whitelisted on that app's `AppProject`).

## `AccessGrant` (ADR-068) — existing, human RBAC

Product-scoped cross-team **access** for a human/group (`subject: group:team-<x>`, `posture: view|operate`) — a
plain, unreconciled, data-only CRD. Convention: one flat file per grant directly under this directory (e.g.
`bravo-reads-alpha-shop.yaml`).

## `ServiceGrant` (ADR-101) — new, workload-to-workload network capability

A governed cross-team **network** capability between two SERVICES (not people): `target` (the PRODUCER —
whose namespace admits traffic) and `subject` (the CONSUMER — whose namespace gets egress), plus the granted
`capability.network` (ports/protocol, optionally L7 `http` method/path narrowing). A dedicated Crossplane
Composition (`service-grant-api`) reconciles a `ServiceGrant` into the two `CiliumNetworkPolicy` halves that
implement it — app teams never hand-author a cross-namespace CNP. The consumer separately declares intent on
their own `XEnvironment` (`spec.dependencies`); `restrict-environment-dependencies` (Kyverno) checks that
declaration against a matching, non-expired `ServiceGrant` at claim admission — mutual consent, neither side
alone can wire a cross-team hop.

**Convention: `gitops/grants/<target.team>/<name>.yaml`** — one per-team SUBDIRECTORY per file, named for the
PRODUCER (`target.team`), who owns the directory, the PR, and the consent it represents. This is enforced by
`.github/scripts/gitops-gate/validate-service-grants.sh` (the load-bearing directory-team ==
`spec.target.team` authorization check) and by Kyverno's `restrict-service-grant-admission`
(`service-grant-policies` chart — only the GitOps controller identity may author/modify one; neither side may
resolve to a hipaa/pci-tier Environment).

No CODEOWNERS line for either kind — per-team ownership is enforced by the gate script's directory-team check,
matching how `gitops/environments/`/`gitops/products/` are governed today.
