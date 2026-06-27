---
name: argocd-app-delivery
description: >-
  How application delivery works on this platform via ArgoCD — the GitOps pull
  mechanism that syncs cluster state from git. Use when adding or editing an
  ApplicationSet / AppProject, wiring a Product's per-Product delivery, setting up a
  PR preview environment, debugging an OutOfSync / sync-failed / "namespace not
  found" Application, or reasoning about the registry-sync apps, sync waves, and the
  platform-service vs tenant delivery roads (ADR-081). Covers the argocd /
  argocd-apps / argocd-clusters modules, the gitops/ registry layout, the
  Release-keyed git generator, digest injection, and the cross-account cluster
  registration. NOT for provisioning the environment/namespace itself
  (`environment-onboarding` / `crossplane-composition-authoring`), NOT for the app's
  build/sign CI (`supply-chain-onboarding`), NOT for writing the app's manifests
  (`authoring-k8s-workloads`).
---

# ArgoCD / GitOps application delivery

ArgoCD runs **only on the platform cluster** (the hub) and manages itself plus the
**preprod** spoke via a registered cluster Secret + cross-account role assumption
(hub-and-spoke). Delivery is **git-driven via ApplicationSets**, not the classic
app-of-apps: Terraform provisions the stable AppProjects, and ApplicationSets fan out
dynamically from `gitops/`, so **creating an environment is a git PR, not a
`terragrunt apply`**. Operational troubleshooting lives in
`docs/runbooks/debug-argocd-sync.md`.

## The three modules

- `infra/modules/argocd/` — the Helm release. EKS Pod Identity (ADR-047, not IRSA),
  Keycloak OIDC SSO (embedded Dex off), team-scoped RBAC CSV generated in the live unit
  from the Teams registry (default policy = deny), ApplicationSet controller on.
- `infra/modules/argocd-clusters/` — registers remote clusters as `argocd`-namespace
  Secrets (label `argocd.argoproj.io/secret-type: cluster`) carrying `awsAuthConfig`
  (clusterName + roleARN) for cross-account EKS-token auth.
- `infra/modules/argocd-apps/` — the AppProjects, registry-sync Applications, and the
  per-Product delivery + PR-preview ApplicationSets (`delivery.tf`).

## The gitops/ registry layout (source of truth)

```text
gitops/
  teams/<team>.yaml                         # Team CR (ADR-063)
  products/<team>/<product>.yaml            # Product CR (repo, tenancy, domains; ADR-069)
  environments/<team>/<product>/<stage>.yaml# XEnvironment claim (reconciled by Crossplane)
  releases/<team>/<product>/<stage>.yaml    # Release record — per-service digest pins (ADR-071)
  grants/...                                # AccessGrant CRs (cross-team, ADR-068) — the registry-sync
                                            #   app references this path, but no grant files exist yet
```

Modules read these with `fileset()`+`yamldecode()` (no external tool). **Registry-sync
Applications** project the git files into cluster CRs; **per-Product delivery
ApplicationSets** read `gitops/releases/**` and deploy the app overlays.

## Sync waves

```text
wave -2  products registry-sync
wave -1  teams registry-sync
wave  0  environments + grants registry-sync
```

Team CRs must exist before XEnvironment admission (the Kyverno envelope gate reads them);
Products before Environments. Registry-sync apps use `ServerSideApply=true` (Crossplane
owns its own fields; we own only the spec). The **per-Product delivery ApplicationSets are
NOT wave-ordered** — they're applied directly by Terraform (`helm_release` /
`kubernetes_manifest`), not as wave-annotated Applications.

## Per-Product delivery (ADR-069)

The per-Product ApplicationSet ships as a passthrough Helm chart,
`charts/applicationset-raw` (Terraform's `kubernetes_manifest` can't represent ArgoCD's
recursive generator schema, so the chart applies the manifest verbatim). It uses a single
**`git`/files generator over `gitops/releases/<team>/<product>/*.yaml`** — one Application
per Release (i.e. per environment that has a promoted digest). (The in-code rationale
comment still says "merge" generator — historical; the live generator is git/files.) The
template:

- names the Application `<team>-<product>-<stage>` (stage derived from the Release's
  `environmentRef`), source = `<Product.repo>/k8s/overlays/<stage>`;
- injects the namespace, the HTTPRoute hostname (if `preview_domain` set), and a per-
  service kustomize `images` override pinning `team-<team>/<product>-<svc>@<digest>` from
  the Release (`templatePatch`);
- `selfHeal=true, prune=true`; **short retry** for first deploys (the overlay carries
  `:placeholder` until CI pins the digest — a long retry would hammer a doomed revision
  for 45 min).

## PR preview environments (ADR-032) — DESIGN INTENT, not yet shipped

> **Verify against code before relying on this.** As of writing, the `argocd-apps`
> module has **no `pullRequest` generator, no `preview_appset`, and no `github_org`/
> `tenants` variable** — the full per-PR ApplicationSet described in ADR-032 lives only in
> the (v2-era) `argocd-apps/README.md`, not in the deployed code.

What **is** wired today: `var.preview_domain` on the standard per-Product delivery
ApplicationSet. When set, the `templatePatch` rewrites the per-stage HTTPRoute host to
`<product>-<team>-<stage>.<preview_domain>` (`delivery.tf`). That's a per-stage host
rewrite, **not** a per-PR ephemeral environment.

The ADR-032 per-PR design (a GitHub `pullRequest` generator creating ephemeral
`<team>-<product>-pr-<n>` Applications with `namePrefix: pr-<n>-`, and an app-repo
`k8s/<stage>/name-reference.yaml` to rewrite Gateway-API HTTPRoute `backendRefs` under the
prefix) is the intended end-state — treat it as roadmap until the generator exists in
`delivery.tf`.

## Platform-service vs tenant delivery (ADR-081)

At the GitOps layer they're **the same road** once the Product is in git: the platform
team has a `gitops/teams/platform.yaml` with a broader `platformTrust` envelope, a
`gitops/products/platform/<svc>.yaml`, an environment claim, and a Release — same
machinery as a tenant app. The platform-trust difference is validated at admission
(Kyverno envelope), not at delivery. `triage-copilot` is the reference instance (its
`gitops/{teams,products,environments}/platform/...` files exist). (Note: platform *agents*
are intended to be provisioned by a separate `XAgent` Composition per ADR-080 — that
Composition is **not yet in `infra/`/`gitops/`**, so treat it as design intent.)

## Add a tenant app (happy path)

1. `gitops/products/<team>/<product>.yaml` (admin-gated PR) + matching
   `gitops/environments/<team>/<product>/` dir.
2. `gitops/environments/<team>/<product>/<stage>.yaml` and an initially-placeholder
   `gitops/releases/<team>/<product>/<stage>.yaml`.
3. App repo: `k8s/overlays/<stage>/kustomization.yaml` (+ `name-reference.yaml` if preview).
4. First CI build signs + pushes to ECR; the promote bot opens a Release PR pinning the
   digest; the gitops gate auto-merges (≤ staging; prod gated); ArgoCD sees the revision
   change, selfHeals, and syncs the overlay with the pinned digest into the env namespace.

## Gotchas

- **Cross-account "i/o timeout"**: after preprod scale-to-zero/restore, the EKS API ENI
  IPs change and the `cross-vpc-dns` PHZ record goes stale → ArgoCD can't reach the API.
  Re-apply `cross-vpc-dns`, then restart argocd / `--hard-refresh`. (Memory: a known
  preprod scale-up recovery step.)
- **"namespace not found"**: Applications sync with `CreateNamespace=false`; the
  namespace is owned by the Environment Composition. If the XEnvironment isn't READY, the
  namespace doesn't exist and sync errors — fix the environment first.
- **Crossplane drift on environments**: Crossplane writes finalizers/`spec.crossplane`
  into claims; ArgoCD sees drift. The registry-sync app uses `ServerSideApply=true`
  (`delivery.tf`); separately there's a cluster-wide `resource.customizations.ignoreDifferences`
  in the `argocd` unit's `argocd-cm` — but note it's still keyed to the **v2 `XTenant`** kind
  (`spec.crossplane`/finalizers), not `XEnvironment`, so an `XEnvironment`-scoped
  customization is currently missing. Re-apply the `argocd` unit if it flaps OutOfSync.
- **Progressive delivery / Argo Rollouts (ADR-056)**: every env workload is a `Rollout`, and prod runs a
  metric-gated **canary** (or blue/green). The rollouts controller mutates two fields at runtime that ArgoCD
  `selfHeal` will otherwise revert mid-rollout — so the **tenant Application `ignoreDifferences`** the Service
  `.spec.selector` (the injected `rollouts-pod-template-hash`) **and** the HTTPRoute `backendRefs[].weight` (the
  Gateway-API plugin's canary weights), in `delivery.tf`. **`ignoreDifferences` alone is NOT enough** — without
  **`RespectIgnoreDifferences=true`** in the Application `syncOptions`, a sync triggered by any *other* change
  still stomps those fields and fights the canary (found in prod; the offline spikes couldn't surface it). The
  per-stage canary shape lives in the app's `k8s/overlays/prod` (scaffolder `deployStrategy`), and the prod
  metric gate queries the hub Mimir via the spoke read route — see ADR-056's as-built section.
- **Backstage ArgoCD token 401**: a Helm apply can drop the minted backstage account
  token from `argocd-cm`; re-mint and update Secrets Manager (`docs/runbooks/backstage-argocd.md`).
- **No offline test for the delivery ApplicationSet generator** — first draft of a
  delivery ApplicationSet is verified only against a live ArgoCD.
- EKS is private (ADR-010): reach it over Tailscale (`cluster-access`), never the public
  endpoint.

## References

- `docs/runbooks/debug-argocd-sync.md` — sync status, cross-account, AppProject, previews
- `docs/runbooks/promote-a-release.md` — promotion (auto ≤ staging, prod gated)
- `docs/runbooks/backstage-argocd.md` — ArgoCD token lifecycle
- `infra/modules/argocd-apps/delivery.tf`, `gitops/{products,environments,releases}/`
- ADRs: 021 (ArgoCD), 032 (PR preview), 047 (Pod Identity), 061 (ingress),
  063 (Team git-native), 067 (domain model), 069 (delivery source-of-truth),
  071 (digest promotion), 081 (platform-service delivery)
