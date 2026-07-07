# How-to: onboard a new Product (a playbook)

**A playbook for putting a new application on the platform.** By the end, your Product exists — with its
container registry, a keyless CI push role, its supply-chain policies, and its delivery apps — all derived
from one small file you'll add to git. Written to be followable **even if this is your first time on the
platform**; read the [orientation](orientation.md) first for the *why*.

> **Working with an AI agent?** Authoring the registry entry is a great agent task — see
> [Doing this with an agent](#doing-this-with-an-ai-agent) for a prompt, the context to attach, and the
> guardrails. Come back here to review its PR.

## What you'll need first

- **A Team to own the Product.** Products are owned by a Team (`gitops/teams/<team>.yaml`). If your team
  isn't in `gitops/teams/`, onboard it first (a Team is a similar small registry file). Check with
  `ls gitops/teams/`.
- **A repo? Only if you're bringing your own.** The **scaffolder creates the repo for you** (Path A) — you do
  *not* need one first; it seeds a new `<team>-<product>` repo from the golden starter. You only need an
  existing repo for the manual Path B. Either way: **one Product = one repo** (the supply-chain trust anchor);
  multiple Services live in that one repo.
- **A name.** The Product's `metadata.name` is `<team>-<product>` (e.g. `alpha-shop`), lowercase-kebab.

## New to the platform? The 60-second model

You're about to make a **GitOps** change — [git is the source of truth](https://opengitops.dev/), and the
platform reconciles reality to match it. Specifically:

- The **Product registry** (`gitops/products/**`) is the single list of every application. Adding a file =
  onboarding an app.
- Three platform units **derive** each Product's infrastructure from that file — a CI push role
  ([GitHub OIDC](https://docs.github.com/en/actions/concepts/security/openid-connect), keyless), the
  supply-chain policies, and the ArgoCD delivery apps. You author *intent*; the platform builds the rest.

You do not provision any of it by hand. Your whole job here is to write one good file and open a PR.

---

## Path A — the Backstage scaffolder (recommended): repo-on-demand

The paved path is the **New Product**
[software template](https://backstage.io/docs/features/software-templates/) — and it doesn't just write a
registry file, it **creates your application**:

1. In Backstage, **Create → New Product**.
2. Fill the form: **team** (your membership is verified server-side — you can only create for your own team),
   **product** name, first **service** (usually `web`), and **language** (Go / Java / Node / Python / Ruby /
   Rust).
3. The template then does the work for you:
   - **creates a new GitHub repo `<team>-<product>`**, seeded from the platform **golden starter** — a working
     app + Dockerfile in your language, the k8s manifests, and the **supply-chain CI already wired** to the
     shared build-sign pipeline (your first push builds, signs, and attests with zero setup);
   - assigns it to your GitHub **team** (the `<team>-` prefix is also the supply chain's unspoofable team
     identity — [ADR-072](../../adrs/072-app-repo-naming-and-team-ownership.md));
   - **opens a platform PR** with your `Product` registry file **and** a first **dev Environment claim**.
4. Review + merge that PR → [What happens on merge](#what-happens-on-merge). Because the CI is pre-wired and a
   dev Environment is claimed, you're moments from a running app — not just a registry entry.

Want to see exactly what gets written, or bringing an existing repo? Use Path B.

## Path B — a direct registry PR (what the form writes)

### Step 1 — create the registry file

Add `gitops/products/<team>/<product>.yaml`. Here's a complete, annotated example for a new `alpha` product
called `checkout`:

```yaml
apiVersion: platform.refplat.org/v1beta1
kind: Product
metadata:
  name: alpha-checkout            # <team>-<product>, lowercase-kebab
spec:
  team: alpha                     # MUST be an existing Team (gitops/teams/alpha.yaml)
  repo: asanexample/alpha-checkout # the ONE repo sourcing this product — the trust anchor
  tenancy: pooled                 # pooled | per-customer
  defaultIsolation:
    compute: dedicated-namespace  # shared-namespace | dedicated-namespace | dedicated-nodes |
                                  #   dedicated-cluster | dedicated-account (Environments may dial UP)
  domains: []                     # vanity hostnames this product owns; [] = use platform hostnames
```

**Field notes** (full schema in the [reference](reference.md)):

- `spec.team` — must match a file in `gitops/teams/`. This drives ownership, access, and on-call.
- `spec.repo` — **singular and load-bearing.** The CI push role will trust *only* this repo, and the verify
  policies will trust *only* images signed from it. One repo per Product; a second app = a second Product.
- `spec.tenancy` — `pooled` unless you genuinely need a dedicated Environment per customer at prod.
- `spec.defaultIsolation.compute` — the floor; most products want `dedicated-namespace`. Regulated tiers
  force higher.
- `spec.domains` — leave `[]` to start; add `{host: shop.example.com, dns: managed}` later when you have a
  custom hostname (ADR-061).

### Step 2 — open the PR

Open a pull request with just that file. Keep it to the one registry file — the
[gitops gate](../policy/orientation.md) classifies your PR as a *Product registration* and validates it:
the team exists, the schema is valid, the name/repo/tenancy are sane. Fix anything it flags; it runs *before*
merge, so mistakes never reach the cluster.

<a id="what-happens-on-merge"></a>

## What happens on merge

You don't run `terragrunt apply`. On merge, `reconcile-on-product-merge.yml` waits for the merge, then
dispatches the **`registry-reconcile`** workflow — a privileged apply of the three derived units. Out of it
come:

- an **ECR repository** per Service (`team-<team>/<product>-<svc>`),
- a **keyless CI push role** federated to `spec.repo` (your pipeline can now push images, no stored keys),
- the **`verify-images-product-<p>` / `verify-attestations-product-<p>`** Kyverno policies,
- one **AppProject + ApplicationSet** ready to deliver your Environments.

> ⚠️ **These don't exist until the reconcile runs** (not at merge instant). If the push role or policies seem
> missing minutes after merge, check that `registry-reconcile` actually ran and succeeded.

## Then what — from registered to running

**Via the scaffolder (Path A), the first two below are already done for you** — the golden-starter repo ships
with supply-chain CI wired, and the PR included a dev Environment claim. For a **bring-your-own repo (Path
B)**, or to add more stages, do them explicitly:

1. **Wire your app's CI** to the shared signing pipeline so its images are signed + attested (Path A: already
   wired). → the `supply-chain-onboarding` skill / [Supply chain](../supply-chain/orientation.md).
2. **Create an Environment** — a Product *at a stage* (`alpha-checkout-dev`) via an `XEnvironment` claim
   (Path A: a dev one was claimed for you; add test / staging / prod the same way).
   → the `environment-onboarding` skill / [Environment API](../environment-api/orientation.md).
3. **Deploy + promote** across stages. → [Delivery](../delivery/orientation.md).

## Verify it worked

- **The registry file is on `main`** and `registry-reconcile` succeeded (check the Actions run).
- **The derived policies exist:** `kubectl --context preprod get clusterpolicy | grep <product>` shows
  `verify-images-product-<product>`.
- **The delivery app exists:** the `argocd-apps`/ApplicationSet has an entry for your Product.
- **The push role exists:** an IAM role trusting `spec.repo` (visible once your CI runs an OIDC push).

## Doing this with an AI agent

Authoring the registry entry is mechanical and well-specified — a good agent task. The risk isn't the YAML;
it's getting the *identity* fields wrong (a typo'd `repo` breaks the trust anchor silently).

**Context to attach:** this playbook, `gitops/products/` (a couple of existing files as examples),
`gitops/teams/` (to confirm the team exists), and the [reference](reference.md) schema.

**A starting prompt:**

> Onboard a new Product `alpha-checkout` owned by team `alpha`, repo `asanexample/alpha-checkout`, following
> `docs/learn/products/how-to-onboard-a-product.md`. Create `gitops/products/alpha/checkout.yaml` matching
> the schema and the existing files' conventions (`metadata.name: alpha-checkout`, `tenancy: pooled`,
> `defaultIsolation.compute: dedicated-namespace`, `domains: []`). **Verify the team `alpha` exists in
> `gitops/teams/` first** — if not, stop and tell me. Open a PR with *only* that one file. Do not touch any
> derived infra (IAM, policies, ArgoCD) — those are reconciled automatically on merge.

**Guardrails to give it:**

- **Confirm the Team exists** before writing the Product — a Product pointing at a missing team fails the gate.
- **`repo` must be exact** — it's a security trust anchor, not a label. No guessing; use the value given.
- **One file, no derived infra.** The agent authors *only* the registry entry; it must not hand-write the
  push role, policies, or ApplicationSet (that defeats the single-source-of-truth model and will drift).
- **`metadata.name` = `<team>-<product>`**, lowercase-kebab; `tenancy` ∈ {pooled, per-customer}; isolation ∈
  the schema enum.

**Review checklist:**

- [ ] `spec.team` matches an existing `gitops/teams/` file; `spec.repo` is exact and singular.
- [ ] `metadata.name` = `<team>-<product>`; enums valid.
- [ ] PR touches *only* `gitops/products/<team>/<product>.yaml` — no derived infra edited.
- [ ] The gitops gate passes.

## Gotchas

- **The Team must exist first.** Onboard the Team (its own registry file) before its first Product.
- **Derived infra materializes on reconcile, not merge.** Give it the workflow run; don't hand-create the role.
- **One repo per Product.** Splitting an app across two repos means two Products, or rethinking the split.
- **Don't edit derived files.** If the push role or a policy is wrong, fix `spec.repo` in the registry and
  re-reconcile — never patch the derived IAM/policy directly (it'll be overwritten and it breaks the model).

## Go deeper

- The model: the [orientation](orientation.md) · the schema + derivations: the [reference](reference.md).
- Next steps: `supply-chain-onboarding` + `environment-onboarding` skills;
  [Supply chain](../supply-chain/orientation.md) · [Environment API](../environment-api/orientation.md) ·
  [Delivery](../delivery/orientation.md).
- Why it's shaped this way: [ADR-069](../../adrs/069-delivery-source-of-truth-product-environment.md) ·
  [ADR-067](../../adrs/067-idp-domain-model.md).
- Substrate: [GitOps principles](https://opengitops.dev/) ·
  [GitHub OIDC](https://docs.github.com/en/actions/concepts/security/openid-connect) ·
  [Backstage software templates](https://backstage.io/docs/features/software-templates/).
