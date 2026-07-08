# Learn: Developer Experience

How a developer gets **Vercel-like DX** on this platform — states intent, gets governed infrastructure —
without learning Crossplane, ArgoCD, Kyverno, or IAM. Two surfaces: **Backstage** (a single pane of glass to
*see* everything) and the **scaffolder** (golden-path templates to *create* things) — where every change is a
pull request the platform reconciles.

**Audience:** developers shipping on the platform, and the platform engineers who build the paved road.
**Before you start:** the [domain model](../domain-model/orientation.md) (the vocabulary the portal renders)
is the one prerequisite.

## Read in this order

1. **[Orientation](orientation.md)** — *"the paved road: intent in, a PR out, reconciled infra."* The BACK
   stack, the two surfaces (Backstage + the scaffolder), and self-service-*with-guardrails*. Metaphor: a
   storefront over a warehouse where every order is a mail-order form.
2. **[Reference](reference.md)** — the dense lookup: the BACK stack, the Backstage module (catalog projection,
   auth, plugins), the scaffolder templates + engine, the guardrails, the status ledger, gotchas.

## Go deep

- **[The Backstage portal](deep-dive-the-backstage-portal.md)** — the catalog as a *projection of git*
  (Team→Group, Product→System, Environment), direct Keycloak OIDC (Dex retired), the read-only scoped plugins
  (Kubernetes / ArgoCD / Cost), and the app-vs-infra split that trips everyone up.
- **[The scaffolder golden paths](deep-dive-the-scaffolder-golden-paths.md)** — the ten templates, three
  traced form → PR → registry → provision (new-product, new-environment, request-promotion), the scaffolder
  engine (schema + Nunjucks + custom `platform:*` actions), and self-service-with-guardrails.

## Then

- What the portal renders: [domain model](../domain-model/orientation.md). Where a form's PR goes:
  [Environment API](../environment-api/orientation.md) + [Delivery](../delivery/orientation.md). The
  hand-authored counterpart: the `environment-onboarding` house skill.
