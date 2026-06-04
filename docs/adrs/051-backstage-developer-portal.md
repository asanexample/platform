# ADR-051: Backstage as the Developer Portal

**Date:** 2026-06-04

**Status:** Accepted — implements the BACK stack's portal layer ([ADR-046](046-back-stack-for-developer-self-service.md)),
authenticates via the centralized Dex broker ([ADR-052](052-centralized-dex-sso-broker.md)), and renders the tenant
model defined by [ADR-049](049-tenant-model-team-tenant-zone.md). Phases 2.0–2.3a are live; 2.4 (live plugins) and
the Phase-3 Scaffolder are planned follow-ups.

## Context

The platform runs on GitOps + Crossplane + Kyverno: tenants are declarative `XTenant` claims in git
([ADR-048](048-federated-per-cluster-crossplane.md)), apps are delivered by ArgoCD, and admission policy is
Kyverno. That machinery is correct but **opaque to developers** — there is no single place to see "what teams,
tenants, apps and infrastructure exist, who owns them, and what state they're in." The BACK stack (ADR-046)
calls for a developer portal as that window, and ultimately as the **self-service vending** surface (templates
that open the claim/app PRs). Backstage is the BACK stack's "B".

This ADR records the decision to adopt Backstage and the shape of that adoption. Several sub-decisions were
open: build vs. buy the portal, how to deploy it, where its catalog data comes from, and how it authenticates.

## Decision

**Adopt upstream Backstage as the developer portal**, in our own repo `asanexample/backstage`, deployed to the
platform cluster and reachable Tailscale-internally at `https://backstage.aws.refplat.org`.

- **Vanilla upstream Backstage, our repo, our signed image.** We track upstream Backstage (currently 1.51) with
  *minimal* customization. The repo's CI builds the app and **cosign-signs + SBOMs** the image to the platform
  ECR (`platform/backstage`), like any first-party workload. The only bespoke code is the catalog projection
  plugin (below) and the thin SSO frontend module — everything else is configuration. Keeping customization
  minimal bounds the long-term maintenance/upgrade surface.

- **Deploy via Terragrunt, not GitOps.** Backstage is **platform infrastructure** (like ArgoCD, Dex,
  cert-manager), not a tenant app, so it is a Terragrunt `helm_release` (the official Backstage chart → our
  image), in `infra/modules/backstage` + its unit. Rolling a new build = bump the unit's `image_tag` to the new
  commit SHA and apply. This keeps the portal out of the very GitOps loop it observes (no bootstrapping cycle).

- **Database is configurable; in-cluster for dev, RDS for prod.** `database.mode` selects in-cluster
  **CloudNativePG** (the default, dev-grade) or managed **RDS** (a prod toggle; the RDS path is a planned
  follow-up). Backstage creates a database per plugin, so the role needs `CREATEDB` (granted declaratively).

- **SSO via the centralized Dex broker (ADR-052), swappable.** Auth is Identity Center —SAML→ Dex —OIDC→
  Backstage, issuer `https://sso.aws.refplat.org`. The vendor-neutral issuer is deliberate: it is the seam at
  which a future self-hosted Keycloak could replace Dex without touching Backstage. Phase 2.1 is **login-only**
  (email-based sign-in resolver); group-based RBAC is deferred to a later phase (no permission framework yet),
  so the **authorization boundary is the SAML app's group assignment**.

- **The catalog is a projection of the authoritative model in GIT — not a scrape of the cluster.** A custom
  Backstage backend **entity provider** (`plugins/platform-projection`) reads the `XTenant` tenant claims from
  the platform repo via a **read-only GitHub App** (no AWS, no cluster credential) and projects them per
  [ADR-049](049-tenant-model-team-tenant-zone.md): **Team → Group**, **Tenant → System** (carrying
  `zone`/`customer`/`tier` as first-class attributes **from day one** — degenerate `default`/`standard` today),
  the Composition's footprint → **Resources**, and app repos' `catalog-info.yaml` → **Components** (discovered
  separately, linked to their System). Git is the source of truth, so the catalog stays correct without
  privileged cluster access; the only cross-account/cluster reads are the read-only **live plugins** (2.4).

- **Staged, each sub-phase independently demoable.** **2.0** bare portal · **2.1** SSO · **2.2** catalog
  discovery (Components) · **2.3** the projection plugin (Groups/Systems/Resources) · **2.4** read-only live
  plugins (Kubernetes, ArgoCD, TechDocs). The **Scaffolder / Software Templates is explicitly Phase 3** — the
  portal is read-only until then. Templates and entity schemas must honor the ADR-049 forward-compat model.

We rejected building a bespoke portal (Backstage is the CNCF-standard for exactly this, with the plugin
ecosystem we want) and rejected a SaaS portal (the catalog must read our internal git/cluster, and the portal
is Tailscale-internal by design).

## Consequences

- **Read-only, internal, low blast radius.** The portal is behind Tailscale on the internal gateway; 2.0–2.3
  need no cluster/AWS credentials at all (the projection reads git). The 2.4 live plugins get their own
  **scoped, read-only** credentials (Kubernetes via a read-only ServiceAccount per the cross-account pattern;
  ArgoCD via a read-only token) — never cluster-admin.

- **Session UX is constrained by SAML.** Identity Center federates via SAML, which cannot issue refresh tokens,
  so Backstage's silent `/refresh` always fails and the in-memory session does not survive a page reload —
  users must re-click "Sign In" on each load (the popup completes silently while the IdP session is alive). No
  Backstage/Dex configuration fixes this; the resolution is to front the portal with an **auth proxy**
  (oauth2-proxy) that owns its own session cookie — tracked in issue #202, documented in
  [`../runbooks/dex-sso.md`](../runbooks/dex-sso.md).

- **Ongoing upgrade surface.** Tracking upstream Backstage is real maintenance. Mitigated by keeping
  customization to the projection plugin + SSO module and treating everything else as config; the signed-image
  pipeline means portal builds are first-party supply-chain artifacts like any other.

- **Forward-compatible entity model.** Because Systems carry `zone`/`customer`/`tier` from the start, the
  catalog needs no entity-model change when the `XTenant` XRD gains those fields (ADR-049 v2) — the projection
  just starts reading real values.

- **Deploy is an image bump.** No GitOps drift-correction for the portal; a new build is an explicit
  `image_tag` change + apply, consistent with the other platform add-ons.
