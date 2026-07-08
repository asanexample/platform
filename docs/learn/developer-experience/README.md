# Learn: Developer Experience

How a developer ships on this platform: state intent, get governed infrastructure back, without
learning Crossplane, ArgoCD, Kyverno, or IAM. There are two surfaces. **Backstage** is a single pane
of glass to see everything; the **scaffolder** hands out golden-path templates to create things. Every
change is a pull request the platform reconciles.

**Audience:** developers shipping on the platform, and the platform engineers who build the paved road.
**Before you start:** read the [domain model](../domain-model/orientation.md) — it's the vocabulary the
portal renders, and the one prerequisite here.

## Read in this order

1. **[Orientation](orientation.md)** — the paved road: intent in, a PR out, reconciled infra. Covers the
   BACK stack, the two surfaces (Backstage and the scaffolder), and self-service with guardrails. The
   metaphor is a storefront over a warehouse, where every order is a mail-order form.
2. **[Reference](reference.md)** — the dense lookup: the BACK stack, the Backstage module (catalog
   projection, auth, plugins), the scaffolder templates and engine, the guardrails, the status ledger,
   and the gotchas.

## Go deep

- **[The Backstage portal](deep-dive-the-backstage-portal.md)** — the catalog as a projection of git
  (Team→Group, Product→System, Environment), direct Keycloak OIDC (Dex retired), the read-only scoped
  plugins (Kubernetes / ArgoCD / Cost), and the app-vs-infra split that trips everyone up.
- **[The scaffolder golden paths](deep-dive-the-scaffolder-golden-paths.md)** — the ten templates, three
  of them traced form → PR → registry → provision (new-product, new-environment, request-promotion), the
  scaffolder engine (schema + Nunjucks + custom `platform:*` actions), and self-service with guardrails.

## Then

- What the portal renders: the [domain model](../domain-model/orientation.md). Where a form's PR goes:
  the [Environment API](../environment-api/orientation.md) and [Delivery](../delivery/orientation.md).
  The hand-authored counterpart: the `environment-onboarding` house skill.
