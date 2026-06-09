# ADR-052: Centralized Dex SSO Broker

**Date:** 2026-06-03

**Status:** Accepted, then **superseded by [ADR-053](053-identity-and-cross-system-authorization-strategy.md) /
[ADR-059](059-identity-topology-pluggable-idp-seam.md)** — Keycloak is now the app-facing IdP of record; Dex is
legacy/being retired. This ADR documents the Phase-2.1 Dex broker for history. Current model:
[identity-and-sso](../architecture/identity-and-sso.md).

## Context

Backstage Phase 2.1 needs SSO. We already bridge AWS Identity Center (a SAML IdP) to ArgoCD via a **Dex**
SAML→OIDC broker that ships *embedded* in the ArgoCD Helm chart (ADR-012). Backstage authenticates via OIDC,
so it needs a Dex too. That raises an architecture question with three answers:

1. **Per-app Dex** — give Backstage its own embedded/standalone Dex, like ArgoCD has its own. Every new app
   that needs SSO gets *another* Dex, and — because each Dex is a distinct SAML SP with its own ACS URL — its
   own **manually-created Identity Center SAML app** and its own **signing certificate to rotate**. The manual
   SAML-app step and cert rotation are the only non-IaC toil in this whole area; per-app Dex multiplies it by N.
2. **Piggyback on ArgoCD's embedded Dex** — add a Backstage `staticClient` to ArgoCD's `dex.config`. Cheapest
   today, but Backstage's OIDC issuer becomes `argocd.aws.refplat.org/api/dex`, coupling Backstage login to
   ArgoCD's lifecycle (an ArgoCD upgrade/outage/redeploy breaks Backstage auth) and overloading a component
   that is semantically "ArgoCD's."
3. **One centralized Dex broker** — a single dedicated Dex serving *many* OIDC clients.

ADR-049's swappability requirement also bears on this: we want to keep the door open to a future self-hosted
Keycloak. Whatever brokers identity is the seam we'd later swap.

## Decision

**Stand up a single, centralized Dex broker** (`infra/modules/dex` + its `dex` unit on the platform cluster),
issuer **`https://sso.aws.refplat.org`** (vendor-neutral host — survives a Keycloak swap), exposed Tailscale-
internal via the shared Cilium Gateway like every other platform service. It serves OIDC `staticClients` from a
data-driven list (`static_clients`); **Backstage is its first client**, and future apps are added as a list
entry — no new Dex, no new SAML app, no new certificate.

- **One Identity Center SAML app, one certificate.** A single new SAML app (ACS/audience
  `https://sso.aws.refplat.org/callback`) feeds the broker's SAML connector; its cert lands in `secrets.hcl`
  as `dex_sso_url`/`dex_sso_ca_data` (mirroring `argocd_sso_*`). Created/rotated once — see
  [`../runbooks/dex-sso.md`](../runbooks/dex-sso.md).
- **Per-client secret, generated + brokered as IaC.** The module generates each client's secret, stores it in
  Secrets Manager (`platform/<id>/oidc`), and External Secrets syncs it into the consuming namespaces. Dex
  reads it via `secretEnv`; the app reads it via an injected env var.
- **Stateless HA.** `storage: kubernetes` (CRD-backed, shared) + 2 replicas, so the shared dependency isn't a
  single point of failure.
- **Decoupled from ArgoCD.** ArgoCD keeps its embedded Dex for now; **migrating ArgoCD onto this broker and
  retiring its embedded Dex is a planned follow-up**, not part of 2.1.

We explicitly rejected #1 (multiplies SAML-app + cert toil; doesn't scale to a multi-app portal) and #2 (wrong
coupling; the issuer leaks ArgoCD's identity).

## Consequences

- **Cost is just naming.** Building the broker vs. a Backstage-only Dex is the same work today; we paid nothing
  extra to get the scalable shape.
- **Shared blast radius.** Dex down ⇒ all SSO down. Mitigated by 2 stateless replicas; acceptable for any IdP.
- **Authn ≠ authz (Phase 2.1).** The broker authenticates; it does not authorize. With Backstage's login-only
  resolver (no permission framework yet), **the authorization boundary is the SAML app's assignment** — assign
  it only to the intended Identity Center groups. Group-based RBAC is a later-phase item.
- **Upstream image.** Dex runs the upstream `ghcr.io/dexidp/dex` image (not our ECR, so not cosign-signed by
  us); pinned via the pinned chart's appVersion, with optional digest-pin. No cluster-wide `verify-images`
  policy applies to the `dex` namespace (those are scoped to `team-*`).
- **Identity Center won't carry groups over SAML.** It does not emit group memberships as a SAML attribute, so
  group-*claim*-based in-app RBAC (a later phase) can't rely on the assertion — it needs the catalog/Identity
  Store or a real IdP. Group *assignment* still works as the entitlement gate; the missing piece is the claim.
- **Per-app SAML signing cert + manual mappings are the operational toll.** Each Identity Center SAML app has
  its own signing certificate (not instance-wide) and its attribute mappings are blank until set by hand — both
  are console-only and were the main bring-up friction (see `../runbooks/dex-sso.md`). A future Keycloak/IdP that
  exposes these via API would remove that toil.
- **The Keycloak seam is now explicit.** Replacing Dex with Keycloak means repointing one issuer URL, not N.
