# ADR-060: Tenant App Hostname Convention — Derive and Inject

**Date:** 2026-06-08
**Status:** Accepted

## Context

A tenant app's public hostname is currently defined by hand in **two** places that must be kept in sync:

1. the **claim's `spec.hostnames`** allow-list (`gitops/tenant-claims/preprod/<team>.yaml`), enforced at
   admission by the Composition-generated `restrict-route-hostnames-team-<team>` Kyverno policy (ADR-029); and
2. the **app repo's `k8s/preprod/httproute.yaml`** — the literal hostname on the route Argo CD deploys.

Nothing derives the hostname and nothing links the two. The `XTenant` XRD describes `hostnames` only as
"route hostnames the team may claim" — free-form. The onboarding runbook standardizes the namespace
(`team-<team>`), the ECR repo (`team-<team>/<app>`), and the IAM roles (`Pod-team-<team>`, `DeveloperAccess-<team>`)
— but **never the hostname**. The result is drift: `team-alpha` shipped as the bare `demo.preprod.aws.refplat.org`
while `team-bravo` shipped as `demo-bravo.preprod.aws.refplat.org`. Two sources of truth, no convention, manual
coordination across a repo boundary — every rename is a multi-repo dance and an opportunity for an admission
denial when the two drift.

The app **name** itself is not the problem: the source of truth is the claim's `spec.apps.<app>` map key, which
already drives the ECR repo (`team-<team>/<app>`), the image-registry policy scope, and the per-app preview
ApplicationSet. The hostname should be derived from that same `(app, team)` identity, not re-declared.

## Decision

**The platform owns tenant app hostnames; they are *derived* from `(app, team, env)` and *injected*, never
hardcoded.** The claim's `spec.apps.<app>` key + `spec.team` are the single source of truth.

### Naming convention

| Kind | Pattern | Example (`app=demo`, `team=alpha`, preprod) |
|------|---------|------|
| Base (stable) | `<app>-<team>.<env-domain>` | `demo-alpha.preprod.aws.refplat.org` |
| PR preview | `<app>-<team>-pr-<n>.<env-domain>` | `demo-alpha-pr-7.preprod.aws.refplat.org` |

`<env-domain>` is a per-cluster constant (preprod → `preprod.aws.refplat.org`). `team-bravo` already matches
this convention; `team-alpha` is migrated off the bare `demo` host.

### Ownership (derive + inject)

- **Allow-list — generated.** The Tenant Composition derives the `restrict-route-hostnames-team-<team>`
  allow-list as `{<app>-<team>.<env-domain>, <app>-<team>-pr-*.<env-domain>}` for every app in `spec.apps`,
  reading `<env-domain>` from the cluster's EnvironmentConfig (`baseDomain`, alongside the existing
  `ecrRegistry`). The free-form `spec.hostnames` is retained only as an **additive override** for genuine
  extras (a vanity domain); the derived hostnames are always permitted.
- **Route hostname — injected.** `argocd-apps` rewrites the HTTPRoute hostname for the stable Application to
  `<app>-<team>.<env-domain>` via a kustomize patch — the same mechanism that already rewrites preview
  hostnames. App repos therefore **do not** hardcode a hostname; their `k8s/preprod/httproute.yaml` carries a
  placeholder the platform overwrites.

### Consequences

- **Single source of truth, zero drift.** Hostnames can no longer disagree between the claim and the app repo;
  there is only one definition (`app_key` + `team`), expanded by convention everywhere it is needed.
- **App repos get simpler** — no hostname to maintain, and no need to know the env domain.
- **Cutover is transition-safe** (a route hostname must be in the allow-list or it is denied): allow both the
  old and the derived host during the migration, switch the injected/derived host, then drop the old entry.
  `team-alpha`'s `demo` → `demo-alpha` migration follows this sequence.
- The convention is enforced by construction (the platform generates both sides), so the onboarding runbook
  only needs to state the pattern, not a sync procedure.

## Implementation outline

1. **EnvironmentConfig**: add `baseDomain` (preprod → `preprod.aws.refplat.org`) next to `ecrRegistry`.
2. **Composition** (`charts/tenant/files/composition.yaml`): generate the `restrict-route-hostnames` allow-list
   from `<app>-<team>` per app + the `-pr-*` wildcard, union with any explicit `spec.hostnames` extras.
3. **argocd-apps**: inject `<app>-<team>.<preview_domain>` into the stable Application's HTTPRoute (mirroring
   the existing preview patch); keep the preview patch as `<app>-<team>-pr-<n>`.
4. **App repos** (`app-alpha`, `app-bravo`): replace the hardcoded HTTPRoute hostname with a placeholder.
5. **Migrate `team-alpha`** `demo` → `demo-alpha` using the transition-safe sequence above; remove the bare
   `demo` allow-list entry once the route has switched.
6. **Runbook**: document the convention in `docs/runbooks/tenant-onboarding.md`.

Relates to ADR-029 (preprod public ingress), ADR-046/048 (the tenant Composition), ADR-049 (the tenant model).
