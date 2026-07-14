# Learn: Onboarding a Product — orientation

How a whole new application gets onto the platform — the repo itself (created on demand, pre-wired for CI), its
container registry, its supply-chain policies, and its continuous delivery — from a form, or one file in git,
with nothing hand-wired per app. This is the day-one paved road, and it's the difference between onboarding an
app in minutes and filing a week of tickets.

**Audience:** platform engineers, and team leads onboarding a new product. It sits on top of
[the domain model](../domain-model/orientation.md) (Team / Product / Service / Environment) — read that first
if those words are fuzzy. It's the sibling of the [Environment API](../environment-api/orientation.md): that
module provisions an environment (a Product at a stage); this one registers the Product itself.

It helps to have seen [Delivery](../delivery/orientation.md), [Policy](../policy/orientation.md), and
[Supply chain](../supply-chain/orientation.md) — this module is where the per-product pieces of all three come
from.

## The question

A new app needs a lot of scaffolding before a single line of it can ship: somewhere to store its images (an ECR
repo), a way for its CI to push those images (a trusted role — but scoped so it can't push as some other team),
the policies that verify its images are signed, and the delivery machinery that rolls it out across stages. Do
that by hand, per app, and you get drift, copy-paste mistakes, and a platform team that's a bottleneck on every
new project.

So where does a new application's identity live, and how does its entire per-product footprint get created —
consistently, safely, without a human wiring each piece?

## One registry entry, everything derives from it

This is the platform's single-source-of-truth instinct applied to onboarding:

> A Product is one declarative file in a git registry. It declares the essentials — who owns it, its repo, its
> tenancy. The platform then derives its entire per-product footprint from that one file: the CI push role, the
> supply-chain policies, the delivery apps. You register the Product; you never wire the pieces.

The registry is the source of truth; every per-product system is a derived view of it. Add a Product = add a
file; the rest materializes. The Product registry (plus the Environment claims) is the single record of every
app — there is no separate hand-maintained per-app config anyone edits by hand.

That last part is the quiet win. The failure mode of onboarding-by-hand isn't one dramatic mistake — it's
drift: the ECR repo exists but the push role was scoped to the wrong repo; the verify policy got added but
named for last month's product; an app ships for months before someone notices its images were never actually
being checked. When every per-product system is derived from one record, those can't silently diverge — there's
exactly one place to be right, and being right there makes everything downstream right. And because the
derivation is code, onboarding the fiftieth product costs what the first did: the platform team isn't in the
loop for a routine app.

Think of a franchise registry. HQ keeps one record per location — owner, address, brand. The signage vendor,
the supply contracts, and the payment terminals each read that one record and set themselves up accordingly;
nobody re-enters the franchise's details into three systems. Register a location, and its whole operational
footprint follows. Where it breaks: unlike humans reading a record, the platform's "vendors" are deterministic
code — the derivation is exact and re-runs every time the registry changes.

## The record — a Product in the registry

Here's `acme`'s `shop` (`gitops/products/acme/shop.yaml`) — the essential spec, with the file's header comment
and `metadata.labels` elided for clarity:

```yaml
apiVersion: platform.refplat.org/v1beta1
kind: Product
metadata:
  name: acme-shop
spec:
  team: acme                        # who OWNS it (→ ownership, access, on-call)
  repo: asanexample/acme-shop       # its source repo — and its supply-chain TRUST anchor
  tenancy: pooled                   # how it shares infrastructure
  defaultIsolation: { compute: dedicated-namespace }
  domains: []                       # any custom hostnames it serves
```

That's the entire declaration of a product. No ARNs, no policy YAML, no ApplicationSet — just what this product
is. Note `spec.repo`: it isn't only documentation, it's the trust anchor the supply chain uses. The CI push
role federates to it, and the verify policies only trust images signed from it (see
[Supply chain](../supply-chain/orientation.md)). One field, doing real security work in two systems.

## The three derivations — where the footprint comes from

Three platform units read the registry (`fileset` + `yamldecode` over `gitops/products/**`) and each derives
its slice per Product. This is the heart of it:

![One Product record fans out on merge into its derived footprint: the `github-oidc` CI push role (OIDC-federated, trusting only the product's repo), the per-product Kyverno verify-images / verify-attestations policies, the `argocd-apps` AppProject + ApplicationSet, and the `github-teams` ownership grant. The ECR repositories are the exception — they materialize when an Environment claim reconciles, not on the Product merge.](images/product-derivation.svg)

- **`github-oidc`** derives a CI role that lets `acme-shop`'s pipeline push to its ECR repo — federated by
  [GitHub OIDC](../supply-chain/orientation.md) so it needs no stored keys, and scoped so the role trusts only
  `spec.repo`. `acme-shop`'s CI can't push as `globex-widgets`.
- **`policy`** derives the per-product Kyverno policies — `verify-images-product-acme-shop` and
  `verify-attestations-product-acme-shop` — so only signed, attested images from shop's repo run (the enforce
  side — Kyverno rejecting non-compliant images at admission; see [Policy](../policy/orientation.md)).
- **`argocd-apps`** derives one AppProject + ApplicationSet per Product, which then fans out one ArgoCD
  Application per Environment (the delivery machinery from [Delivery](../delivery/orientation.md)).

A fourth unit, `github-teams`, also derives from this registry — it grants the owning org-Team `push` on the
`<team>-<product>` repo. The three above are
the per-product footprint, which is why we foreground them; `github-teams` is the ownership grant.

All three are computed from the same `acme-shop.yaml`. Change the registry, they re-derive. There's no second
place where "the list of products" lives to drift out of sync.

This declare-once-then-derive shape is the platform's signature move, not a one-off.
[Identity](../identity/orientation.md) declares people and roles in git and derives access into every system;
[self-service resources](../self-service-resources/orientation.md) declare abstract intent and derive the
least-privilege IAM; here you declare a Product and derive its footprint. Once you see it, the whole platform
reads the same way: a small governed declaration in git, and deterministic code that projects it outward. Learn
it once, and every subsystem is less surprising.

![The declare-once-then-derive pattern recurring across the platform: in Identity you declare people and roles and derive access into every system; in self-service resources you declare abstract intent and derive the least-privilege IAM; and here — the highlighted row — you declare a Product and derive its footprint. One shape, three subsystems.](images/declare-then-derive.svg)

## The paved road — repo-on-demand, not just a registry entry

You don't hand-author anything from memory, and — this is the part worth dwelling on — you don't even bring a
repo. The Backstage New Product scaffolder creates the application for you:

1. **You fill a form** — team (membership verified server-side, so you can only create for your own team),
   product name, first service, and language (Go, Java, Node, Python, Ruby, Rust).
2. **It creates a new GitHub repo, `<team>-<product>`**, seeded from the platform's golden starter — a working
   app skeleton + Dockerfile in your language, the Kubernetes manifests, and the supply-chain CI already wired
   to the shared signing pipeline. The owning GitHub team is granted `push` on the repo later — by the
   `github-teams` derived unit on reconcile, not at creation — and that `<team>-` name prefix is the
   unspoofable team identity the supply chain trusts. This is repo-on-demand: you don't wire up
   a repo, you get one that already builds, signs, and deploys.
3. **It opens a platform PR** adding your `Product` registry file and a first dev Environment claim — so
   registering the Product and standing up its first environment are one action.
4. **The gitops gate validates** that PR (team exists, schema, repo/tenancy sane) before merge; on merge,
   `reconcile-on-product-merge.yml` dispatches the `registry-reconcile` workflow, which runs the privileged
   apply of the [derived units](#the-three-derivations--where-the-footprint-comes-from) (the push role, verify
   policies, delivery apps, and the org-Team push grant) — no human runs a `terragrunt apply`. (The per-Service
   ECR repos aren't part of that apply — they're provisioned by the Environment Composition when the environment
   is claimed.)

So the real day-one experience is: fill a form, review a PR, merge, and you have a repo that already
builds+signs, a registered Product, and a running dev environment. Prefer to bring your own repo, or script it?
A direct registry PR works too — see the [how-to](how-to-onboard-a-product.md); you then point `spec.repo` at
your existing repo and wire its CI yourself.

## Where a Product fits — the objects around it

A Product doesn't live alone; it's the middle of the ownership model
([domain model](../domain-model/orientation.md)):

- A **Team** (`gitops/teams/<team>.yaml`) owns Products and declares the envelope that bounds them (allowed
  stages, quota caps, which self-service engines — see
  [Self-service resources](../self-service-resources/orientation.md)).
- A **Product** is the application. It has one or more Services (deployable units → ECR repos
  `team-<team>/<product>-<svc>`).
- An **Environment** is a Product at a stage (`acme-shop-dev`), provisioned by the
  [Environment API](../environment-api/orientation.md) from a claim.

Onboarding a Product is registering that middle object; Environments and Services then hang off it.

## When it breaks — the ones you'll actually hit

- **"I merged my Product but the push role / policies aren't there."** The derived units are created by the
  reconcile apply that runs after merge (`registry-reconcile`), not at the merge instant. Check that workflow
  ran and succeeded — the footprint materializes when it does.
- **"The gate rejected my Product PR — 'team not found'."** A Product must point at an existing Team
  (`gitops/teams/<team>.yaml`). Onboard the Team first; it's the same kind of small registry file.
- **"Can I split my app across two repos?"** Not as one Product — `spec.repo` is singular because it's the
  supply-chain trust anchor. Two repos = two Products (or rethink the split); multiple Services in one repo is
  the supported shape.
- **"The derived IAM/policy looks wrong — can I patch it?"** No. Fix the registry (`spec.repo`, usually) and
  let it re-derive. Hand-patching a derived resource is drift: it's overwritten on the next reconcile, and it
  breaks the single-source-of-truth guarantee the whole model rests on.

## Go deeper

- The mechanism + schema + gotchas: the [Reference](reference.md).
- **Onboard one yourself** (the step-by-step playbook): [How-to: onboard a new Product](how-to-onboard-a-product.md).
- The pieces that derive from the registry: [Delivery](../delivery/orientation.md) ·
  [Policy](../policy/orientation.md) · [Supply chain](../supply-chain/orientation.md); the vocabulary:
  [the domain model](../domain-model/orientation.md).
