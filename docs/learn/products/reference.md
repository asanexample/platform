# Learn: Onboarding a Product — reference

A lookup reference. For the model behind these fields, see the [orientation](orientation.md).

## The `Product` schema

`gitops/products/<team>/<product>.yaml`, `kind: Product` (`platform.refplat.org/v1beta1`),
`metadata.name: <team>-<product>`:

| field | required | values / notes |
| --- | --- | --- |
| `spec.team` | ✅ | owning Team; an Environment's `team` must equal this (Kyverno-enforced). |
| `spec.repo` | ✅ | the single owner/repo sourcing the Product's Service(s); the supply-chain trust anchor. |
| `spec.tenancy` | ✅ | `pooled` (customers logical) \| `per-customer` (a dedicated Environment per Customer at prod). |
| `spec.defaultIsolation.compute` | | `shared-namespace` → `dedicated-namespace` → `dedicated-nodes` → `dedicated-cluster` → `dedicated-account` (floored by tier; an Environment may dial up). |
| `spec.restrictWithinTeam` | | if true, even team members need an explicit AccessGrant; auto-true for pci/hipaa. |
| `spec.domains[]` | | vanity hostnames the Product **owns** (the allow-set); each `{host, dns: managed\|external}`. An Environment binds a subset. |

The Team (`gitops/teams/<team>.yaml`) owns Products and sets the envelope that bounds them — allowed
stages, quota caps, and the self-service `allowedEngines`.

## The derivations (registry → footprint)

Each unit does `fileset` + `yamldecode` over `gitops/products/**` and derives per Product:

| unit | derives | keyed on |
| --- | --- | --- |
| **`github-oidc`** | a CI push role (GitHub OIDC-federated, keyless) → push to the Product's ECR | `spec.repo` — the role trusts *only* that repo |
| **`policy`** | `verify-images-product-<p>` + `verify-attestations-product-<p>` (signed + attested, from the repo) | `spec.repo` |
| **`argocd-apps`** | one AppProject + ApplicationSet per Product → fans out an ArgoCD App per Environment that has a Release | `metadata.name`, `spec.team`; the git-files generator fans out over `gitops/releases/<team>/<product>/*.yaml` (one App per Environment that has a Release) |
| **`github-teams`** | the owning org-Team's `push` grant on the `<team>-<product>` repo | `spec.repo` (bare repo name), `spec.team` |

Per-**Service** ECR repos are `team-<team>/<product>-<svc>`.

## The paved road

1. **Author** — Backstage **New Product** scaffolder (form → PR) or a direct PR adding the registry file.
2. **Validate** — the **gitops gate** (`gitops-gate.yml`) checks team-exists / schema / repo / tenancy on the
   PR, before merge.
3. **Reconcile** — on merge, `reconcile-on-product-merge.yml` waits for merge then dispatches
   `registry-reconcile` (a privileged apply of `github-oidc` / `policy` / `argocd-apps` / `github-teams`) — the derived units
   *don't exist* until this runs. No manual `terragrunt apply` for routine onboarding.

## Gotchas

- **The derived units don't exist until the reconcile apply.** A freshly-merged Product's role/policies/apps
  materialize when `registry-reconcile` runs — not at merge time. If something's missing, check that
  workflow ran.
- **One repo per Product.** `spec.repo` is singular by design (it's the trust anchor). Multiple Services live
  in that one repo (→ `team-<team>/<product>-<svc>` ECR repos); a second repo means a second Product.
- **The gitops gate runs from the trusted base (`main`).** Same trap as elsewhere — a PR that changes the
  gate's own allow-lists can't pass its own gate; land enabling changes first.
- **Rename the repo → edit one field.** `spec.repo` is the single source; changing it re-derives the push
  role's trust and the verify policies' anchor. Don't hand-edit the derived IAM/policies.
- **`metadata.name` is `<team>-<product>`.** The derivations and ECR paths assume it; keep the convention.

## Glossary

- **Product** — an application; the registry's unit of onboarding. Owned by a Team, sources from one repo.
- **registry** — `gitops/products/**`, the git-native single source of truth for Products.
- **derive** — compute per-product infra (`fileset`+`yamldecode`) rather than hand-maintaining it.
- **reconcile** — the privileged apply of the derived units after a registry change.
- **Service** — a deployable unit of a Product → one ECR repo, one ApplicationSet fan-out entry.

## Go deeper

- **Onboard one** (step-by-step): [How-to: onboard a new Product](how-to-onboard-a-product.md).
- The consumers: [Delivery](../delivery/orientation.md) · [Policy](../policy/orientation.md) ·
  [Supply chain](../supply-chain/orientation.md) · [Environment API](../environment-api/orientation.md).
