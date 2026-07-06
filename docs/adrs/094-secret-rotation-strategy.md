# ADR-094: Secret Rotation Strategy

**Date:** 2026-07-04

**Status:** Proposed — closes the design half of the "no rotation on any Secrets Manager secret"
gap (#811, TD2-02, part of #809; Tier 1 of the security posture register, epic #1152). The
classification and the per-secret **owner** decision land here; the realization is phased (below)
and **verification is gated on cluster unpark** — nothing here can be validated while parked, and
per platform practice it lands on **preprod before platform**.

## Context

Every *identity* credential on the platform is already short-lived and federated — humans via AWS
SSO, CI via GitHub Actions OIDC, and all pod→AWS access via **EKS Pod Identity** ([ADR-047](047-pod-identity-as-aws-identity-standard.md)).
There are **no long-lived IAM access keys anywhere**; the `restrict-iam-users` SCP forbids creating
them. That is the hard half of rotation, and it is done.

What is **not** rotated is a bounded set of **static credential values** that Terraform (or CNPG)
generates once and parks in AWS Secrets Manager for the cluster's lifetime. The audit
(`docs/tech-debt-audit-2026-06-26-second-pass.md`, #811) found **all 23 platform + 3 preprod
secrets** at `Rotation: null`: Keycloak admin + per-app OIDC client secrets, seed-user passwords,
Grafana admin, in-cluster Postgres (CNPG) passwords, Backstage session + oauth2-proxy cookie
secrets, and a set of **externally-minted** credentials — 5 GitHub App private keys, a GitHub PAT
(`platform/github/argocd-pat`), Tailscale OAuth + API key, Cloudflare token, PagerDuty routing keys.
There is a **manual** runbook (`docs/runbooks/secret-rotation.md`) for four of them; everything else
is undocumented and unrotated.

"Auto-rotation" is really **three** missing primitives, and conflating them is why the gap has stayed
open:

1. **A rotation trigger.** `random_password` is idempotent — generated once, never regenerated. There
   is zero `aws_secretsmanager_secret_rotation` in the codebase.
2. **Restart-on-change.** ESO rewrites the k8s Secret on its `refreshInterval`, but env-var consumers
   keep the old value until the pod restarts. Only a few modules restart via a `configHash`
   (Keycloak); there is **no cluster-wide Reloader**.
3. **Rotation observability.** `NextRotationDate` is always empty; there is no metric, alert, or audit
   of secret *age* or of rotation success. Tracking is a calendar reminder.

We are **not** adopting HashiCorp Vault. [ADR-024](024-secrets-management-architecture.md) and
[ADR-070](070-tenant-app-config-and-secrets.md) both park Vault behind an explicit revisit trigger
(a real need for **dynamic/leased** secrets, or a hard cross-cloud-neutral-backend requirement).
Rotating static secrets does not fire that trigger, and a new Tier-0 system is exactly the cost we
just paid for Keycloak. The strategy below stays inside the existing **ESO + Secrets Manager + Pod
Identity** seam.

## Decision

Rotation difficulty is a function of **who owns the secret's value and whether both sides are
controllable.** We therefore classify every secret and pick a mechanism per class, rather than one
mechanism for all. We also build the three missing primitives once, shared across classes.

### The classification

| Class | Definition | Examples | Value owner | Mechanism |
|-------|------------|----------|-------------|-----------|
| **A — Terraform two-sided** | TF (or CNPG) controls *both* the credential and its consumer | Keycloak OIDC client secrets (TF sets the `keycloak_openid_client` secret **and** the SM value); Grafana admin; Backstage session; oauth2-proxy cookie; platform-directory DB roles (CNPG `managed.roles` + `passwordSecret`) | Terraform / CNPG | **Terraform-driven scheduled rotation** — a `time_rotating` keeper on `random_password` + a scheduled `terragrunt apply` on the ARC runners. One apply rotates both sides in lockstep; no coordination, no drift |
| **B — External-provider** | Value is minted by a third party | Tailscale OAuth / API key; PagerDuty routing keys; GitHub App private keys (Backstage discovery, scaffolder, ARC); Cloudflare token; GitHub/Slack IdP secrets; the `argocd-pat` | 3rd-party console / API | **Provider-specific.** Native SM rotation Lambda *only* where the provider supports create-new-before-revoke-old overlap; otherwise **scheduled-manual + expiry alerting**, blast-radius-ordered |
| **C — Already keyless** | No static secret exists | GitHub Actions OIDC; all Pod Identity (incl. CNPG backups); AWS SSO; KMS annual key rotation (enabled) | AWS / federated | **Nothing to rotate. Expand this class** — every secret we can *delete* by moving to federation is a rotation problem that ceases to exist (e.g. replace the `argocd-pat` with a GitHub App) |
| **D — Tenant workload secrets** | Do not exist yet | [ADR-070](070-tenant-app-config-and-secrets.md), Proposed, rebuild-gated | (future) | **Design rotation in from day one** — do not retrofit |

The load-bearing insight: **most platform secrets are Class A**, and Class A rotation is nearly free
because Terraform already owns both sides. The Keycloak OIDC client secrets are the archetype —
`keycloak-config` sets `client_secret = random_password.client[...]` on the client **and** writes the
same value to `platform/keycloak/<id>-oidc`, so regenerating the `random_password` rotates both
atomically on the next apply.

### Class B breakdown — automatable vs manual

Class B splits more usefully than "auto vs manual." The real divide is **whether the provider
exposes a programmatic rotate path** (an API or a Terraform provider resource) versus **console-only
generation**. Crucially, several "external" secrets are already **Terraform-provider-managed**, which
means they **collapse into the Class-A mechanism** (a `time_rotating` keeper + scheduled apply) rather
than needing a bespoke Secrets Manager rotation Lambda.

**Automatable — has an API / TF-provider rotate path (prefer the Class-A scheduled apply):**

| Secret | Path | Rotate path | Notes |
|--------|------|-------------|-------|
| Cloudflare API token | `platform/cloudflare/api-token` | Cloudflare "roll token" API endpoint, or re-create via the `cloudflare_api_token` provider resource | The only one that could justify a native SM rotation Lambda (roll is in-place); otherwise fold into scheduled apply |
| Tailscale OAuth client | `platform/tailscale/oauth` | `tailscale_oauth_client` provider resource — re-apply mints a new client + secret | Already in the runbook; no native two-secret overlap, so a brief operator restart |
| PagerDuty routing keys | `platform/pagerduty/<team>-routing-key` | `pagerduty` provider recreates the service integration (new key) | Low sensitivity (write-only alert ingest); recreate-not-roll → short swap window |

**Manual — console-only generation, no programmatic create:**

| Secret | Path | Why manual | Approach |
|--------|------|------------|----------|
| GitHub App private keys (Backstage discovery, scaffolder, ARC) | `platform/backstage/github-app`, `…/scaffolder-github-app`, ARC app | GitHub has **no API to generate an App private key** — UI only (multiple keys can be active at once, so the swap itself is zero-downtime) | Scheduled-manual + expiry alerting |
| GitHub PAT | `platform/github/argocd-pat` | PATs are UI-created; no rotation API | **Retire it** → GitHub App (Class C — delete the secret; the audit's own recommendation) |
| GitHub OAuth App secret (Keycloak IdP) | `platform/keycloak/github-idp` | Client-secret reset is UI-only | Scheduled-manual + alerting; low frequency |
| Slack app secret (Keycloak IdP) | `platform/keycloak/slack-idp` | UI-only | Scheduled-manual + alerting; low frequency |
| Tailscale API key | `platform/tailscale/api-key` | 90-day expiry; it is the *bootstrap* credential (chicken-and-egg to mint its own successor) | Automatable in principle via the Tailscale keys API; currently manual with an 80-day reminder |

So Class B mostly collapses: Tailscale OAuth / PagerDuty / Cloudflare fold into the Class-A "re-apply"
path, and the residual truly-manual set is the **GitHub + Slack credentials + the Tailscale API key**
— handled by scheduled-manual + the rotation-age alerting primitive, with the `argocd-pat` retired
outright. Very little actually warrants a bespoke rotation Lambda.

> **Verify at build time.** Provider rotation-API capabilities change. The specific claims above
> (Cloudflare roll endpoint, the Tailscale / PagerDuty provider resources) must be re-confirmed
> against current provider docs before wiring — treat this table as the design intent, not verified
> ground truth.

### The three shared primitives

1. **Reloader.** Deploy a Reloader (Stakater or equivalent) watching ESO-owned Secrets and issuing a
   `rollout restart` on the owning Deployment/Rollout/StatefulSet when the value changes. This is the
   keystone that turns rotation from a manual dance into a hands-off event, and it serves **every**
   class. A new small platform module.
2. **Rotation observability.** A scheduled Lambda/CronJob reads `DescribeSecret.LastChangedDate` and
   emits a `secret_age_days` metric into the LGTM+P stack, with Grafana alerts → PagerDuty when a
   secret exceeds its per-class policy age. The CI apply also emits a rotation success/failure signal.
   This upgrades the "Future: Automated Expiry Notifications" stub already sketched in the rotation
   runbook.
3. **Refresh-interval tiers.** Apply the 24h/1h/15m ESO `refreshInterval` tiers ADR-024 defined but
   never wired — shorter intervals for rotation-eligible secrets so a rotated value propagates
   promptly.

### The one hard guardrail: single owner per secret

The failure mode that will bite is **Terraform and a rotation Lambda fighting over the same value**
(each reverts the other → drift, or a rotated value clobbered on the next apply). Rule: **exactly one
owner per secret.** If Terraform owns it (Class A), *never* attach a rotation Lambda. If SM native
rotation owns it (Class B), Terraform must `ignore_changes` on the secret version and must **not**
manage the `random_password`. The owner is recorded per-secret in the inventory this ADR seeds.

### Tenant workload secrets (Class D)

Rotation here is a **design input to ADR-070's realization**, not a retrofit. Two honest sub-cases:

- **Platform-generated tenant secrets** (e.g. a DB credential minted by the Environment Composition)
  → auto-rotate exactly like Class A, plus Reloader in the tenant namespace.
- **BYO external secrets** (a dev pastes a third-party API key) → the platform **cannot** silently
  rotate someone else's provider credential. The story is a **"rotate" action in the portal**
  (audited, per ADR-070 §5) + **expiry reminders** (primitive 2, extended to tenant paths) — not
  silent auto-rotation.

### Notable special cases

- **In-cluster CNPG ≠ RDS.** AWS's managed DB rotation templates target RDS/Aurora/Redshift/
  DocumentDB and **do not apply** to the in-cluster CloudNativePG databases. Rotate those via CNPG
  `managed.roles` + `passwordSecret` (Class A), not a Lambda.
- **Keycloak bootstrap admin.** `KC_BOOTSTRAP_ADMIN_*` seeds the admin on first boot; afterwards
  Keycloak owns the credential. Rotating it needs the Keycloak admin API (a password reset), not just
  an env-var swap + restart — so it is a Class B special case, sequenced late, not a Class A quick win.

### Phasing

| Phase | Scope | Live cluster? |
|-------|-------|---------------|
| **0** | This ADR + the per-secret inventory/owner table | No |
| **1** | Deploy Reloader; rotation-age metrics + alerts; apply the refresh-interval tiers; `time_rotating` scaffolding + the scheduled CI-apply job (extends [ADR-065](065-self-hosted-github-actions-runners-arc.md)) | Author now, verify preprod after unpark |
| **2** | Class A rotation, lowest-risk first: oauth2-proxy cookie & Backstage session (rotation just invalidates sessions) → Keycloak OIDC clients → Grafana admin → CNPG managed-role passwords | Verify preprod → platform |
| **3** | Class B: native SM rotation or scheduled-manual + alerting, highest blast radius first (Keycloak admin special case; GitHub App keys; retire `argocd-pat`; Tailscale; PagerDuty) | Yes |
| **4** | Class D: fold rotation into ADR-070 realization | Rebuild-gated |

## Consequences

### Positive

- **Closes #811 with a coherent design**, not a pile of one-off Lambdas. The classification tells you
  the mechanism for any given secret and for any secret added later.
- **No new Tier-0 system.** Reuses ESO + Secrets Manager + Pod Identity + the existing ARC CI-apply;
  Reloader and a metrics CronJob are the only new components.
- **Class A is nearly free** — Terraform already owns both sides, so rotation is a keeper + a
  scheduled apply, with no drift and no coordination problem.
- **The primitives are class-agnostic** — Reloader, age metrics, and refresh tiers benefit every
  secret, including future tenant secrets, and are **authorable now while parked.**
- **Expands the keyless posture** (Class C) — the strongest rotation is a secret that no longer
  exists; retiring the `argocd-pat` for a GitHub App is a concrete instance.

### Negative

- **A scheduled `terragrunt apply` is a new automation surface.** It extends ADR-065's CI-apply but
  adds drift-detection and prod-gating requirements, and a bad apply now has a time trigger.
- **Class B stays partly manual.** GitHub App private keys, the Tailscale API key, and the Cloudflare
  token have no clean auto-rotate path; the honest outcome is scheduled-manual + alerting, not silent
  rotation.
- **Reloader restarts are disruptive if mis-scoped** — it must watch only ESO-owned Secrets and
  respect PDBs / graceful-drain (ADR-085), or a rotation becomes an availability event.

### Risks

- **Owner-fight drift** if the single-owner guardrail is violated — the top risk, mitigated by
  recording the owner per-secret and never double-owning.
- **Unverifiable while parked.** Everything in Phases 1+ is authored against parked clusters; it must
  be verified on **preprod first**. Do not mark any of it live until then.
- **Doc drift to reconcile.** ADR-024's "Auto-rotated / 15m / DB passwords rotated by Secrets Manager"
  row was aspirational (never built) and its IRSA language predates ADR-047. Reconcile it as part of
  this work.

## Relationships

- **Closes the design half of** #811 (TD2-02) / epic #1152; **builds on**
  [ADR-024](024-secrets-management-architecture.md) (secret store, per-account isolation),
  [ADR-025](025-secret-naming-convention.md) (naming/path-scoping),
  [ADR-019](019-external-secrets-operator.md) (ESO sync), [ADR-047](047-pod-identity-as-aws-identity-standard.md)
  (keyless pod→AWS), and [ADR-065](065-self-hosted-github-actions-runners-arc.md) (the CI-apply the
  scheduled rotation extends).
- **Feeds** [ADR-070](070-tenant-app-config-and-secrets.md) — tenant-secret rotation is designed into
  its realization rather than retrofitted.
- **Does not adopt** Vault — the ADR-024 / ADR-070 revisit trigger (dynamic/leased secrets) is
  unchanged and unfired.
- **Supersedes nothing**; the manual `docs/runbooks/secret-rotation.md` remains the break-glass /
  emergency path and is extended, not replaced.
