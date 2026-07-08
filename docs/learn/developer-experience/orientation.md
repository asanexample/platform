# Learn: Developer Experience — orientation

How a developer gets **Vercel-like DX** on top of all this machinery — states intent, gets governed
infrastructure — without ever learning Crossplane, ArgoCD, Kyverno, or IAM. Two halves: a **single pane of
glass** to see everything (Backstage), and **golden paths** to create things (the scaffolder) — where every
change is a pull request the platform reconciles.

**Audience:** developers shipping on the platform, *and* the platform engineers who build the paved road.
**Before you start:** the [domain model](../domain-model/orientation.md) (Team / Product / Service /
Environment — the vocabulary the portal renders) is the one prerequisite. Helpful but optional:
[Environment API](../environment-api/orientation.md) and [Delivery](../delivery/orientation.md) — this module
is the *front door* to both.

## The question

The platform underneath is deliberately deep: Crossplane provisions environments, ArgoCD delivers apps,
Kyverno enforces admission, Keycloak does identity, the LGTM+P stack does observability. Each is the right
tool — and each has its own CLI, CRD, and mental model. A developer who has to learn *all* of them to ship one
service has, in effect, **no platform**. So:

**How do you give a developer a Vercel-like experience — "push code, get a URL" — over a governed,
compliance-aware, multi-tenant substrate, without exposing (or trusting them with) the machinery?**

## The one idea: the paved road — intent in, a PR out, reconciled infra

Here's the whole module in a sentence:

> **The developer states *intent* — a form in a portal, or a git push — and the platform turns it into a
> **pull request to the git registries**, which the normal GitOps path (Gate → ArgoCD → Crossplane)
> reconciles into real infrastructure. The developer names *what* (team, product, stage, a bucket); the
> platform **derives** everything security-sensitive (IAM, ECR, namespace, Kyverno scope, routing). Two
> surfaces make it work: **Backstage** — a single pane of glass to *see* everything — and the **scaffolder**
> — golden-path templates to *create* things. And a load-bearing rule ties them together: the portal never
> writes to anything directly; **every change is a PR.**

This is the **BACK stack** (ADR-046): **B**ackstage (the form) → **A**rgoCD (delivery) → **C**rossplane (the
control plane) → **K**ubernetes. The order matters and it's the whole philosophy: the **control plane was
built first**, and Backstage is a *thin portal over real, reconciled APIs* — never a button that fires an
imperative pipeline. The portal makes the platform *visible and orderable*; it doesn't *become* the platform.

> **The metaphor: a storefront over a warehouse.** The warehouse (the git registries + the cluster) holds the
> real inventory; **Backstage is the storefront** that makes it browsable and orderable. And every "order" is
> a **mail-order form with guardrails** (a scaffolder template): you tick boxes on a catalog card — team,
> product, stage, language — drop it in the outbox (the PR), and a clerk (the Gate) checks it's a *legal*
> order before the warehouse (Crossplane) ships it. **Where it breaks:** unlike a real storefront, this one
> **never touches the warehouse directly** — it can't hand you goods off the shelf, only place an order that
> git and the Gate fulfil. That constraint *is* the governance.

Now the tour: the pane of glass, then the golden paths, then the guardrails that make self-service safe.

---

## Stop 1 — the single pane of glass: Backstage (a projection of git)

A developer opens `backstage.aws.refplat.org` (internal, via Tailscale) and sees **their** Products and
Environments, who owns what, and each one's health and cost — without touching terragrunt or a CRD. That's
the **Software Catalog**, and its key design fact is what keeps it honest:

**The catalog is a *projection of the git registries* — not a scrape of the cluster.** A backend provider
reads this repo's git-native registries through a **read-only** GitHub App and projects them:

- `gitops/teams/<team>.yaml` (a `Team`) → a catalog **Group**
- `gitops/products/<team>/<product>.yaml` (a `Product`) → a **System**
- `gitops/environments/<team>/<product>/<stage>.yaml` (an `XEnvironment` claim) → an **Environment**

So the browse experience is a direct rendering of the [domain model](../domain-model/orientation.md)
(Team → Product → Service → Environment) — and because **git is the source of truth**, the catalog stays
correct with *no privileged cluster access* and can't drift from what's declared. On top of the catalog sit
**read-only, scoped** plugins that show the platform's own view: the **Kubernetes** plugin (live workload
health, reading via a Pod-Identity *viewer* role that can't see Secrets), the **ArgoCD** plugin (deploy
health), and the **Cost** tab (per-team spend vs the team's declared budget). Never cluster-admin — the portal
*shows*, it doesn't *wield*.

> **One thing that trips everyone up:** the Backstage **app** (the image, its custom plugins, the Cost tab
> itself) is a *separate repo*; this infra repo only controls the *deployment*. So "I grepped the backstage
> module and the Cost tab isn't there" is the classic wrong-place error — the plugin ships in the app image;
> the infra side is often a single line elsewhere. Two repos, one portal.

The [Backstage deep dive](deep-dive-the-backstage-portal.md) covers the projection, the direct-Keycloak-OIDC
auth (Dex is retired), the plugins, and the app-vs-infra split in full.

---

## Stop 2 — the golden paths: the scaffolder (forms that open PRs)

Seeing is half of it; the other half is *creating*. Instead of hand-writing a `Product` file + an
`XEnvironment` claim + wiring IAM, a developer fills in a **form** and the **scaffolder** opens a **PR to the
git registries**. The template *is* the paved road, encoded. There are ten of them, covering the whole
lifecycle — the important ones:

- **new-product** — creates the app repo from a golden starter *and* opens a platform PR adding the `Product`
  registry entry + a first `dev` `XEnvironment`.
- **new-environment** — a new Environment (Product × Stage): PRs an `XEnvironment` claim.
- **new-resource** — self-service S3 / SQS / SNS / DynamoDB on a Service: patches the claim; the platform
  derives least-privilege IAM.
- **request-promotion** — the dev → test → staging → prod ladder: resolves the digest already running at the
  source stage and PRs a `Release` for the target — *the same signed artifact moves up, no rebuild*.
- **onboard/offboard-person**, **new-team**, **deprovision-\***, **hello-world** — round out identity,
  envelopes, and reversible wind-down.

The mechanism is always the same shape: **form (a JSON-schema the portal renders) → steps (render a YAML
skeleton, then `publish:github:pull-request`) → a PR link.** Trace `new-environment`: you pick team, product
(a picker that only shows Systems your team owns), and stage; the template renders a `kind: XEnvironment`
claim to `gitops/environments/<team>/<product>/<stage>.yaml` and opens a PR. On merge, ArgoCD's registry-sync
projects it and Crossplane provisions the namespace, quota, network policy, and Pod-Identity — and the
[Environment API](../environment-api/orientation.md) takes it from there. You named a stage; you got a
governed environment.

The [scaffolder deep dive](deep-dive-the-scaffolder-golden-paths.md) traces new-product, new-environment, and
request-promotion end to end, and covers the custom actions (like `platform:verify-team-membership`).

---

## Stop 3 — self-service *with guardrails*: why every change is a PR

Vercel-like DX with none of Vercel's blast radius — the trick is that "self-service" here is **self-service
with guardrails**, and there are three of them:

1. **The schema constrains the ask.** The form is a JSON-schema: you can only pick a stage inside your team's
   *envelope*, an engine in your `allowedEngines`, a product your team owns. You can't *express* an illegal
   request.
2. **The PR keeps a human (or a gate) in the loop — calibrated to blast radius.** Low-risk, already-proven
   changes **auto-merge** (a ≤-staging promotion of an already-signed digest). Privilege grants and drains are
   **reviewer-merged, never auto** (a new team grants an envelope; a decommission drains workloads).
   Irreversible, high-stakes actions need **named approval** (prod promotion → a release-approver, with author
   ≠ approver; a product purge → an admin). The Gate is the toll booth: most traffic waved through, the
   on-ramps to prod and to deletion staffed.
3. **The platform derives the dangerous parts — you never touch them.** You name *intent* (team, product,
   stage, an access level like `read`/`readwrite`); the platform **derives** the ECR repo, the namespace, the
   Kyverno image-scope, and — critically — the **IAM**, least-privilege, deny-set-validated. This is
   *registries-as-single-source* (ADR-069): `argocd-apps`, `policy`, and `github-oidc` all read the same
   `Product` entry, so there's one truth and no drift between what you asked for and what got wired.

Behind those, the same request is checked by **four independent layers** — the portal's permission policy, a
server-side `verify-team-membership` step that binds the run to your own team, the gitops **Gate** (schema +
envelope shift-left), and **Kyverno** re-enforcing the envelope at admission. No single bypass compromises it.
That's why a developer can be handed real power safely: the guardrails aren't in the developer's hands.

---

## The honest status — what's live vs designed

- **Live:** Backstage Phase 2 at `backstage.aws.refplat.org` (verified running) — direct Keycloak OIDC,
  catalog projection (v3), and the Kubernetes / ArgoCD / Cost plugins. The scaffolder is **enabled** —
  team members self-serve the non-privileged paths (new-environment / new-resource / request-promotion /
  new-product); privileged templates (`new-team`, offboarding) are gated server-side. Those paths have been
  proven end to end (the `alpha/shop` product went the whole way).
- **Known live gaps (from the templates' own headers, not speculation):** `new-product`'s *repo-creation* step
  403s until the scaffolder GitHub App is broadened org-wide (the registry-PR half works); the gitops Gate's
  **auto-merge isn't armed yet** — a reviewer merges even the low-risk cases today.
- **Designed / not wired:** **TechDocs** — serving this very learning corpus *inside* Backstage — exists in
  the image but isn't wired (tracked in #938). It's why these docs use absolute source links: they'll survive
  the move into TechDocs. Also: an RDS-backed prod database mode (dev runs in-cluster Postgres today).

The shape to hold: the *pane of glass* and the *golden paths* are built and exercised; what's maturing is the
**friction** — arming auto-merge, broadening the GitHub App, moving the docs in — not the model.

## When it breaks — the ones you'll actually hit

- **"Backstage sign-in 503s."** The single in-cluster auth Postgres blipped and the OIDC client cached a
  failed discovery — `kubectl rollout restart deploy/backstage`.
- **"I added a config key in the module and the feature is silently doing nothing."** A config key with no
  matching schema in the app image is *silently ignored* — you substitute against the image's existing shape;
  you can't invent a new config section from the infra side.
- **"The Cost tab / a plugin isn't in the backstage module."** Right — it ships in the *app* repo's image; the
  infra side is usually one line in a *different* unit. Check the app repo.
- **"`new-product` failed creating my repo."** Known gap — the scaffolder GitHub App isn't org-wide yet, so
  repo creation 403s; the registry PR still opens.
- **"My new environment/product isn't in the catalog yet."** The catalog projects from *merged* git — it
  appears after the PR merges and projection catches up, not when the PR opens.

## Recap — say it back

Cold: *what is the developer experience here, in one breath?* If you can say —

> "**Vercel-like DX over a governed substrate** — the **BACK stack**: a developer states **intent** (a
> **Backstage** form or a git push), the **scaffolder** turns it into a **PR to the git registries**, and
> GitOps (Gate → ArgoCD → Crossplane) reconciles it. Two surfaces: Backstage is the **single pane of glass**
> — a **read-only projection of git** (Team→Group, Product→System, Environment) with scoped plugins — and the
> **scaffolder** is the **golden paths** — forms that open PRs. **Every change is a PR**, and it's
> **self-service *with guardrails***: the schema constrains the ask, the Gate reviews by blast radius, and the
> platform **derives** the IAM/ECR/namespace so the developer never touches the dangerous parts. Portal +
> scaffolder are live; TechDocs and armed auto-merge are the maturing edges" —

— then you understand the front door to the whole platform.

## Go deeper

- [The Backstage portal](deep-dive-the-backstage-portal.md) — the catalog projection, direct Keycloak OIDC,
  the read-only plugins (Kubernetes / ArgoCD / Cost), and the app-vs-infra split.
- [The scaffolder golden paths](deep-dive-the-scaffolder-golden-paths.md) — the ten templates, three traced
  form → PR → registry → provision, the scaffolder engine, and self-service-with-guardrails.
- The lookup: the [Reference](reference.md). Related: [domain model](../domain-model/orientation.md),
  [Environment API](../environment-api/orientation.md), [Delivery](../delivery/orientation.md),
  [Onboarding a Product](../products/orientation.md).
