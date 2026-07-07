# Learn: Onboarding a Product

How a whole new application gets onto the platform — its registry, CI push role, supply-chain policies, and
delivery — from **one file in git**, nothing hand-wired per app. The "day one" paved road, and the
single-source-of-truth model behind it.

**Audience:** platform engineers and team leads onboarding a new app. Sits on
[the domain model](../domain-model/orientation.md) (Team / Product / Service / Environment); it's the sibling
of the [Environment API](../environment-api/) (that provisions an *environment*; this registers the
*Product*).

**Before you start:** the [domain model](../domain-model/orientation.md). Seeing
[Delivery](../delivery/orientation.md) / [Policy](../policy/orientation.md) /
[Supply chain](../supply-chain/orientation.md) helps — this is where their *per-product* pieces come from.

## Read in this order

1. **[Orientation](orientation.md)** — the one idea (*one registry entry, everything derives from it*), the
   real `alpha-shop` record, the **derivations** (github-oidc / policy / argocd-apps, plus github-teams), and the paved
   road (scaffolder → gate → reconcile-on-merge).
2. **[Reference](reference.md)** — the `Product` schema, the derivations table, the paved road, and gotchas.

**Onboard one yourself:** **[How-to: onboard a new Product](how-to-onboard-a-product.md)** — a
newcomer-followable, AI-forward playbook (both the Backstage scaffolder path and a direct registry PR).

## Then, to go deeper

- The pieces that derive from the registry: [Delivery](../delivery/orientation.md) ·
  [Policy](../policy/orientation.md) · [Supply chain](../supply-chain/orientation.md) ·
  [Environment API](../environment-api/orientation.md).
- Why it's shaped this way: [ADR-069](../../adrs/069-delivery-source-of-truth-product-environment.md)
  (registry as source of truth) · [ADR-067](../../adrs/067-idp-domain-model.md) (the domain model).
