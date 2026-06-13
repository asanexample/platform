# Environment API schema + render tests

Offline validation of the **Environment API** ([ADR-067](../../../../docs/adrs/067-idp-domain-model.md),
[schema](../../../../docs/architecture/platform-domain-api.md)) — the `XEnvironment` XRD
(`../charts/environment-api/templates/xenvironment-xrd.yaml`) and the projected `Team` / `Product` / `AccessGrant` CRDs.
**the sole API surface since the cutover** (the v1alpha2 `XTenant` surface was removed).

Two harnesses, both cluster-free:

- **`run.sh`** — `crossplane beta validate` checks the example claims/records against each XRD/CRD's OpenAPI v3
  schema + `x-kubernetes-validations` CEL rules (no cluster, no Composition, no Docker). CI job **Environment API
  Schema**.
- **`render.sh`** — `crossplane render` of the **Composition** (`../charts/environment-api/files/composition.yaml`)
  via Docker-run Pipeline functions; asserts the rendered Environment footprint (namespace
  `<team>-<product>[-<customer>]-<stage>`, product-scoped ECR/Pod-Identity, quota, netpols, RoleBinding,
  restrict-images/route-hostnames). Fixtures in `render/` (pinned `functions.yaml` + `environmentconfig.yaml`).
  CI job **Environment Composition Render**.

```text
environments/          valid XEnvironment claims that MUST pass (demo-dev first-deploy, shop-bigbank-prod
                       per-customer pci) — also used by render.sh
environments-invalid/  XEnvironment claims that MUST be rejected (schema/enum/CEL)
products/              valid Product records that MUST pass        ; products-invalid/  rejected
grants/                valid AccessGrant records that MUST pass    ; grants-invalid/    rejected
teams/              valid v1alpha3 Team records that MUST pass  ; teams-invalid/  rejected
```

`run.sh` also validates the LIVE git-native objects (`gitops/teams`, `gitops/products`, `gitops/environments`)
against the CRDs — giving onboarding PRs a real schema gate in CI, not just human review.

Run locally:

```bash
infra/modules/crossplane/.environment-api-tests/run.sh       # crossplane CLI (+ helm)
infra/modules/crossplane/.environment-api-tests/render.sh    # crossplane CLI + docker
```

Scope: schemas + the Composition footprint. The **Kyverno envelope policy** that reads the projected Team/Product
during admission (the cross-object checks: tier/stage ∈ envelope, team == Product.team, customer-iff,
quota ≤ cap, IAM deny-set) is validated separately by the `../.kyverno-tests` behavioral suite
(`restrict-environment-envelope`, #387).
