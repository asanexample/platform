# ADR-070: Tenant Application Config & Secrets

**Date:** 2026-06-11

**Status:** Proposed — a **new platform capability**. The v3 domain model ([ADR-067](067-idp-domain-model.md))
gives tenants rich per-environment *infra* but nothing for the most common developer need: per-stage
**application config + secrets**. **Rebuild-gated** for the deep wiring; the **schema reservation** lands in F1
so the `XEnvironment` shape is complete.

## Context

Today a tenant app that needs a `DATABASE_URL` or an API key has **no platform-provided way to get it.** The
ESO `ClusterSecretStore` is platform-scoped; the Composition mints **no** per-tenant secret store or
`ExternalSecret`; ADR-024/025/026 are platform-level; the demo apps hardcode env vars. For an IDP whose pitch is
"push code, it runs," this is the missing half of "it runs" — and it pushes developers to stash secrets in worse
side-channels (Slack, local `.env`).

The constraints that make secrets the hard half: a value must **never touch git**, yet be **per-stage**,
**developer self-service** (no ticket to set a prod secret), and **tenant-isolated**.

## Decision

A **portal-first** config & secrets capability — the Vercel/Heroku model — built on the platform's existing
seam ([ADR-019](019-external-secrets-operator.md) ESO + Secrets Manager + Pod-Identity isolation), **not** a new
secrets system.

### 1. Backend: cloud-native store, brokered by ESO (not Vault, yet)

App secrets live in the **cloud-native secret store** — **AWS Secrets Manager today** — brokered by **ESO**. We
do **not** introduce HashiCorp Vault now:

- We already run ESO + Secrets Manager + the per-tenant IAM/Pod-Identity isolation pattern (ADR-024/025/026/041)
  — **zero new Tier-0 system** (we just learned that cost with Keycloak).
- The DX is **backend-agnostic** (ESO brokers any provider), so Vault buys nothing on the experience.
- **Multi-cloud is the ESO per-cloud seam** ([ADR-058](058-per-cloud-tenant-composition-strategy.md)): the same
  neutral API writes to Key Vault on Azure / GCP SM on GCP, selected by **placement**, the dev never naming the
  backend. Vault's one-neutral-backend advantage duplicates a seam we have.
- **Vault is parked behind a revisit trigger:** a real need for **dynamic/leased secrets**, or a hard
  cross-cloud-neutral-backend requirement. It would slot in behind the *same* ESO interface.

**Layout:** one secret per `(team, product, stage)` holding all its keys as a JSON blob (cost: avoids per-key
`$0.40/mo` cardinality) at `…/tenants/<team>/<product>/<stage>`. Lower-sensitivity config may use the cheaper
SSM Parameter Store.

### 2. DX: portal-first write-through (+ platctl through the same API)

```text
Dev → Backstage form  (or  platctl secret set <env> KEY)
    → Backstage backend  (the SOLE broker; its Pod-Identity role, scoped to tenant paths)
    → Secrets Manager   (…/tenants/<team>/<product>/<stage>)
    → ESO ExternalSecret (minted per Environment) → k8s Secret → pod (envFrom)
```

Developers only ever touch the top (form / CLI). **Backstage is the only writer** — devs never get direct store
access; **platctl calls the Backstage secrets API**, so there is **one** authz path and **one** audit trail.

### 3. Config vs secrets — a deliberate split

- **Config (non-secret)** → **git.** Per-stage values (`LOG_LEVEL=debug`) live on the Environment claim
  (`services.<svc>.config: {KEY: value}`) — diffable, PR-reviewable. The Composition renders a **ConfigMap**.
- **Secrets** → **the store, never git.** Values go through the write-through path above; the Environment claim
  holds **no values**. The Composition mints an **`ExternalSecret`** per environment → a k8s Secret.
- **The contract lives on the Service** (`catalog-info.yaml`, env-agnostic): which keys are `config` vs
  `secrets`. That drives which fields the portal shows and what the Composition wires.

The pod consumes both via `envFrom` (the ConfigMap + the Secret).

### 4. Write authz — prod is gated (separation of duties)

Secret **writes** follow the same `stage × tier` posture as everything else ([ADR-040](040-platform-engineer-access-model.md)/[ADR-068](068-product-scoped-and-cross-team-access-model.md)):

- **dev / staging** — any team member, self-service (low blast radius).
- **prod** — **gated** like prod promotion: a prod secret write is a prod mutation, so it needs
  `team-admin` / `release-approver`. A developer requests; an approver applies.
- **regulated (`pci`/`hipaa`)** — stricter (approval + audit; dual-control candidate).

### 5. Reveal — gated and audited, **not** blanket-hidden

Secret values **are revealable** in the UI — blanket "no read-back" is mostly theater (the values are already
role-readable in the store; hiding them only degrades the legit "check the current value" workflow and pushes
secrets to worse channels). Reveal is made safe by **controls, not concealment**:

- **Permission-gated, symmetric with write** — if your posture lets you *set* a secret at a stage, it lets you
  *reveal* it (so **prod reveal is gated**, dev/staging is team-self-service, regulated stricter).
- **Every reveal is audited** — who revealed which key, which env, when. The real control: no *quiet* harvest;
  each view is an attributable, logged event.
- **Per-key, deliberate** — reveal one key at a time; **no bulk export / "show all".**
- **Optional step-up for prod reveal** — re-auth/confirm before showing a prod value (a hijacked session can't
  silently dump prod).

By default the UI shows key **names + metadata** (last-updated, who); **reveal** is the privileged, audited,
one-key action.

### 6. Isolation, audit, and the schema reservation

- **Isolation:** per-tenant path + IAM scoping (ADR-024/025/026); ESO reads only the tenant's path into the
  tenant namespace; a **Kyverno backstop denies cross-tenant `ExternalSecret` refs** (an `ExternalSecret` in
  `team-a-…` may only target the team-a path).
- **Audit:** every set / rotate / delete / **reveal** logged (who, when, which key, which env — **never the
  value**) via CloudTrail + Backstage.
- **Schema (lands in F1):** **reserve `services.<svc>.config` and `services.<svc>.secrets`** on the
  `XEnvironment` schema now (like `resources` is reserved) so the shape is complete; the realization (the
  write-through API, ESO wiring, the gating, audit, the portal UI, `platctl secret`) is the **secrets
  paved-road** phase, not F1.

## Consequences

- **Closes the biggest hole in the IDP** — "push code, set your env vars, it runs," self-service, with prod
  protected. No new Tier-0 system; reuses ESO + Secrets Manager + Pod-Identity.
- **Honest security posture:** reveal is gated + audited rather than hidden — convenient for authorized roles,
  attributable against insiders, no false sense of protection.
- **Config is git-native** (reviewable, promotable with the digest); **secrets never touch git.**
- **Multi-cloud-ready** behind the ESO seam; Vault adoptable later behind the same interface if a trigger fires.
- **Cost** is bounded by the one-secret-per-`(tenant, env)` blob layout; SSM for low-sensitivity config.
- **Scope honesty:** F1 only **reserves** the fields; the capability is a dedicated phase. Until it ships,
  tenants still have no secrets — so sequence the paved-road early relative to real workloads.

## Relationships

- **New capability for** [ADR-067](067-idp-domain-model.md) (the per-env config/secrets the domain model lacked);
  **reserved in** [platform-domain-api.md](../architecture/platform-domain-api.md) (Open-questions #11).
- **Builds on** [ADR-019](019-external-secrets-operator.md) (ESO), [ADR-024](024-secrets-management-architecture.md)/[ADR-025](025-secret-naming-convention.md)/[ADR-026](026-cross-account-secret-isolation.md)
  (secret store, naming, per-tenant isolation), [ADR-041](041-pod-identity-for-tenant-workloads.md) (tenant
  workload identity), and the [ADR-058](058-per-cloud-tenant-composition-strategy.md) per-cloud seam.
- **Authz** (write + reveal gating) derives from [ADR-040](040-platform-engineer-access-model.md) `stage × tier`
  and the [ADR-068](068-product-scoped-and-cross-team-access-model.md) `team-admin` / `release-approver` roles.
- **Contrast:** [ADR-066](066-sops-encrypted-config-secrets.md) (SOPS-in-git) is the **platform's own** config
  secrets; tenant app secrets are **store-brokered, never-in-git** — a deliberately different model for the
  self-service, reveal-in-UI use case.
