# Learn: Secrets & Config — rotation & lifecycle (deep dive)

The platform keeps secrets in two planes: SOPS-encrypted config in git, and AWS Secrets Manager
fronted by [ESO](https://external-secrets.io/) for runtime credentials. This page is about the third
thing — how a static credential gets changed without knocking a workload over, and, honestly, how much
of that is **built** versus **designed**.

Read this part first, because it reframes everything below: automated rotation **does not exist** today.
No rotation controller, no age metric, no timer. What exists is a classification plus a manual
runbook covering four secrets. Everything below that sounds like machinery is a design — it isn't
running, and we flag the line each time.

## The problem — and why the scary half is already done

Most of the win is already banked. Every **identity** credential on the platform is short-lived and
federated: humans authenticate through AWS SSO, CI through [GitHub Actions
OIDC](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect),
and every pod→AWS call through [EKS Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html).
There are **no long-lived IAM
access keys anywhere** — the `restrict-iam-users` SCP forbids creating them. Those credentials expire
on their own; rotating them is the cloud's problem, not ours. That's the hard half of rotation, and the
[identity plane](../identity/orientation.md) already covers it.

What's left is a bounded set of static values that Terraform (or [CloudNativePG](https://cloudnative-pg.io/))
generates once and parks in [AWS Secrets Manager](https://docs.aws.amazon.com/secretsmanager/latest/userguide/intro.html)
for the cluster's lifetime. All 23 platform + 3 preprod secrets sit at `Rotation: null` — Keycloak OIDC
client secrets, seed-user
passwords, Grafana admin, in-cluster Postgres passwords, the Backstage session and oauth2-proxy cookie
secrets, and the externally-minted tokens (GitHub App keys, Tailscale, Cloudflare, PagerDuty).

"Auto-rotation" is not one thing. It's three separate missing primitives, and conflating them is why
nobody shipped it.

1. **A rotation *trigger*.** Terraform's `random_password` is idempotent — generated once on first
   apply, never regenerated. There is **zero** `aws_secretsmanager_secret_rotation` in the codebase
   (verified: the only hits are in vendored provider changelogs). Nothing ever decides to change a value.
2. **Restart-on-change.** Even if the value changed, ESO rewrites the Kubernetes Secret but an env-var
   consumer keeps the cached old value until its pod restarts. The new key is on the peg; nobody picked
   it up.
3. **Rotation *observability*.** `NextRotationDate` is always empty; there's no age metric and no alert.
   You find out a secret is stale from a calendar reminder, if at all.

This is why you can't just rotate everything on a timer: a rotated secret that a running pod has cached
isn't a security win, it's an **outage**. So rotation has to be classification-driven — change each
secret by a mechanism that matches who controls it and whether both sides move together.

## The classification — four classes

The core idea: difficulty is a function of who owns the value and whether both sides are
controllable. Four classes, one mechanism each.

| Class | Owns both sides? | Mechanism | Examples |
| --- | --- | --- | --- |
| **A — Terraform two-sided** | Yes — TF/CNPG owns the credential *and* its consumer | `time_rotating` keeper on `random_password` + a scheduled `terragrunt apply` on the ARC runners → both sides move in lockstep, no drift | Keycloak OIDC client secrets (the archetype); Grafana admin; Backstage session; oauth2-proxy cookie; CNPG `managed.roles` passwords |
| **B — External provider** | No — value minted by a third party | Native SM rotation Lambda *only* where the provider supports new-before-revoke overlap; else scheduled-manual + expiry alerting, blast-radius-ordered | GitHub App keys; Tailscale; PagerDuty; Cloudflare; GitHub/Slack IdP secrets |
| **C — Keyless** | N/A — no static secret exists | **Nothing to rotate.** Keep *expanding* this class | GitHub OIDC; all Pod Identity (incl. CNPG backups); AWS SSO; annual KMS key rotation |
| **D — Tenant** | Don't exist yet (rebuild-gated) | Design rotation in from day one; do not retrofit | (future) |

Most platform secrets are Class A, and Class A rotation is nearly free — Terraform already owns both
sides. The archetype is the Keycloak OIDC client secret. In the `keycloak-config` module (verified in
`infra/modules/keycloak-config/main.tf`), one `random_password.client` value is written to two places
in a single apply — the Keycloak client itself (`client_secret = random_password.client[each.key].result`)
and the Secrets Manager version at `platform/keycloak/<id>-oidc`. Regenerate that `random_password` and
both sides rotate atomically on the next apply. The only missing piece is the trigger: a `time_rotating`
keeper that causes the `random_password` to regenerate on a schedule. Add a keeper, run apply on a timer,
done.

> Think of re-keying a building. It isn't "cut a new key" — it's cut the new key *and hand it to every
> tenant at the same instant*, or you've locked people out. Class A is the case where the locksmith also
> owns the tenants' keyrings: one visit swaps the lock and every copy together, which is why it's cheap.
> Where it breaks: for Class B, a third party cut the lock and only *they* can cut the new key. You wait
> on the locksmith, and there's a gap between "old key revoked" and "new key in hand" unless the provider
> lets both keys work at once.

### Class B splits on "does it have a rotate API?"

Class B is more interesting than auto-vs-manual. The real divide is whether the provider exposes a
programmatic rotate path. Several "external" secrets turn out to be Terraform-provider-managed, and those
collapse into the Class-A path — a keeper plus a scheduled apply, no bespoke Lambda:

- **Tailscale OAuth** (`tailscale_oauth_client`), **PagerDuty** routing keys, and the **Cloudflare** token
  all have a provider resource or roll API, so re-apply mints a new value. Fold them into the scheduled apply.

The genuinely-manual residual is small: **GitHub App private keys** (GitHub has no API to generate an App
key — UI only, though multiple keys can be active at once so the swap is zero-downtime), the **GitHub and
Slack IdP secrets** (console-only resets), and the **Tailscale API key** (90-day expiry, console-only, and
it's the bootstrap credential — chicken-and-egg to mint its own successor). These get scheduled-manual plus
the age-alert primitive. And one class of secret gets deleted rather than rotated: replacing a GitHub PAT
with a GitHub App moves it from Class B into Class C entirely. The best kind of rotation is a secret
that ceases to exist.

> Design intent, not verified ground truth. The provider rotate-API claims —
> the Cloudflare roll endpoint, the Tailscale/PagerDuty provider resources — must be re-confirmed against
> current provider docs before wiring. Treat the table as the plan, not a promise.

### Two special cases worth teaching

- **In-cluster CNPG is not RDS.** AWS's managed-rotation Lambda templates target RDS/Aurora/Redshift/
  DocumentDB — they do not apply to the in-cluster CloudNativePG databases. You rotate those the Class-A
  way: change the password in CNPG's `managed.roles` + `passwordSecret`, which Terraform owns on both sides.
- **The Keycloak bootstrap admin is a Class B trap hiding in Class A.** `KC_BOOTSTRAP_ADMIN_*` only seeds
  the admin on first boot; afterwards Keycloak owns that credential in its own database. Rotating it isn't
  an env-var swap + restart — that would just re-seed on a fresh boot and drift from what Keycloak actually
  stores. It needs a Keycloak admin-API password reset, so it's sequenced late as a Class B special case,
  not treated as a Class A quick win.

## The three shared primitives — built once, serve every class

Rotation isn't one machine; it's three primitives that compose: get the new value into the Secret fast,
get the consumer to use it, then prove it happened.

1. **Reloader** *(the keystone — not deployed)*. A controller ([Stakater Reloader](https://github.com/stakater/Reloader)
   or equivalent) that watches ESO-owned Secrets and issues a `rollout restart` on the owning
   Deployment/Rollout/StatefulSet when the value changes. This is what turns rotation from a manual dance
   into a hands-off event, and it serves every class. Two hard constraints: it must be scoped to only
   ESO-owned Secrets (a cluster-wide restart-on-any-change is a foot-gun), and it must respect
   PodDisruptionBudgets and graceful-drain
   — otherwise a rotation becomes an availability event, which defeats the point.
2. **Rotation observability** *(not built)*. A scheduled Lambda/CronJob reads `DescribeSecret.LastChangedDate`
   and emits a `secret_age_days` metric into the LGTM+P stack; Grafana alerts to PagerDuty when a secret
   exceeds its per-class max age. This upgrades the runbook's "Future: Automated Expiry Notifications" stub
   into a real signal.
3. **Refresh-interval tiers** *(defined but never wired)*. The refresh-tier design specifies
   24h / 1h / 15m ESO `refreshInterval` tiers — shorter for rotation-eligible secrets, so a rotated
   value lands promptly. Verified live: every ExternalSecret today syncs at a flat 1h; the tiers exist only
   on paper.

They compose in order: refresh tiers get the new value into the k8s Secret quickly, Reloader restarts the
consumer so it actually uses it, age metrics prove the rotation happened and nothing went stale. Miss the
middle one and you've re-keyed the lock but left everyone holding the old key.

## The one-owner guardrail — the top risk

The single most dangerous mistake is letting **two owners fight over one value**. If Terraform manages a
secret and you also attach a Secrets Manager rotation Lambda to it, they clobber each other: the Lambda
rotates the value, the next `terragrunt apply` reverts it to the `random_password` result (or vice-versa) —
permanent drift, or a rotated credential silently overwritten. The rule is absolute: **exactly one owner
per secret.**

- **Class A (Terraform owns it):** never attach a rotation Lambda. Terraform's scheduled apply is the only
  rotation path.
- **Class B (SM-native rotation owns it):** Terraform must `ignore_changes` on the secret version and must
  not manage the `random_password` at all.

The owner is recorded per secret in the inventory — that inventory is the actual Phase-0
deliverable.

> Same building: send two locksmiths to the same door on the same morning and each installs *their* lock
> over the other's; the tenant's key now fits neither. One owner per lock, always. The inventory is the
> sign-out sheet that says which locksmith owns which door.

## Why not Vault

Isn't this what [HashiCorp Vault](https://developer.hashicorp.com/vault) is for? Deliberately, no. The
strategy parks Vault behind an explicit revisit trigger: a real need for **dynamic / leased**
secrets, or a hard **cross-cloud-neutral-backend** requirement. Rotating static secrets fires neither.
ESO + Secrets Manager + Pod Identity already cover the need; Vault would be a whole new Tier-0 system to run
— the operational cost the platform already carries for Keycloak — and keyless-first (Class C) keeps shrinking the
problem rather than adding a system to manage it. The strongest rotation strategy isn't a better vault; it's
fewer secrets.

## The honest status — built vs designed

Where each piece actually stands:

| Piece | Status | Verified against |
| --- | --- | --- |
| Classification + owner inventory | **Design only** — no cluster resources | — |
| Stakater Reloader | **Not deployed** — no module exists | Only `reloader` hits are Alloy `configReloader = { enabled = false }` sidecars in `observability-alloy` / `observability-events` — a false positive |
| `time_rotating` / `aws_secretsmanager_secret_rotation` | **Zero** in the codebase | grep — only vendored provider changelogs |
| Rotation-age metric / alert | **Not built** | The only secrets alerts in `observability/alerts/curated.yaml` are `ExternalSecretNotReady` / `ClusterSecretStoreNotReady` — **sync-failure** alerts, not age |
| ESO refresh tiers | **Not wired** — flat 1h everywhere | Live: every ExternalSecret at `1h` |
| Manual rotation runbook | **Live** | `docs/runbooks/secret-rotation.md` — 4 secrets (Cloudflare, Tailscale API key, Tailscale OAuth, ArgoCD OIDC) + compromised-secret response |

The phasing: **P0** = ADR + inventory (no cluster). **P1** = deploy Reloader, age metrics/alerts, refresh
tiers, `time_rotating` scaffolding, scheduled CI-apply — author now, verify preprod after unpark. **P2** =
Class A lowest-risk-first (oauth2-proxy cookie & Backstage session → Keycloak OIDC → Grafana → CNPG). **P3**
= Class B. **P4** = Class D folds into the tenant road. All verification is gated on unpark, preprod before platform.

So: nothing above is automated today. Rotation is a classification design plus a four-secret manual runbook
— and that's fine. The hard half (identity) is done, and the static-secret half now has a coherent plan
instead of a pile of one-off Lambdas.

## Gotchas that teach

- **"I rotated the secret and nothing changed."** ESO re-synced the k8s Secret, but the pod cached the old
  value in an env var. Without Reloader (not deployed) you restart by hand — the ArgoCD OIDC runbook shows
  the manual dance (`force-sync` annotation → re-apply → the `configHash` restart). That's primitive #2 in
  miniature, done by hand.
- **`NextRotationDate` is always empty.** Not a bug — no secret has `aws_secretsmanager_secret_rotation`
  configured, so there's nothing to populate it. `describe-secret` gives you `LastChangedDate`; age is
  something you compute, not something the API tracks for you (yet).
- **A rotation that ignores PDBs is an outage generator.** Reloader restarting every replica of a
  single-owner Deployment at once = downtime. Rotation must ride the same graceful-drain / PDB machinery as
  any other rollout. "Change the locks" only works if you hand out the new keys without locking
  everyone out mid-swap.
- **The "external" secret that's secretly Class A.** Tailscale OAuth feels like a third-party token you must
  rotate by hand, but it's a `tailscale_oauth_client` Terraform resource — re-apply mints a new one. Check
  whether a provider resource owns it before writing a Lambda; most of Class B collapses this way.
- **Don't double-own.** The instinct to "add a rotation Lambda for safety" on a Terraform-managed secret is
  exactly the drift bug. One owner, recorded in the inventory, no exceptions.

## Go deeper

- [Runbook — Secret Rotation Procedures](../../runbooks/secret-rotation.md) — the live four-secret manual
  path and the compromised-secret response.
- `infra/modules/keycloak-config/main.tf` — the Class-A archetype: one `random_password.client` written to
  both the Keycloak client and the Secrets Manager version.
- [Stakater Reloader](https://github.com/stakater/Reloader) (the candidate for primitive #1),
  [AWS Secrets Manager rotation](https://docs.aws.amazon.com/secretsmanager/latest/userguide/rotating-secrets.html)
  (native rotation + why the managed templates are RDS-shaped), and
  [ESO ownership & deletion policy](https://external-secrets.io/latest/guides/ownership-deletion-policy/)
  (who owns a synced Secret) — all verified reachable.
- Back to the [Secrets & Config orientation](orientation.md) · related: [Identity & access](../identity/orientation.md).
