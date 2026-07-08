# Learn: Secrets & Config — reference

Look-up, not a lesson. Build the model in the [orientation](orientation.md) first. Verified against code +
live (ESO is up: the operator + 2 ClusterSecretStores + 16 ExternalSecrets, all synced). No secret *values*,
account IDs, or emails appear here — only non-sensitive *paths* and mechanism.

## The model

**Best secret = none.** Three moves, in order: **eliminate** (federate — Pod Identity/OIDC/keyless cosign) →
**seal in git** (SOPS, for *config identifiers*) → **vault + sync** (Secrets Manager + ESO, for *runtime
credentials*). Two planes, never crossed:

| | **Config-in-git (SOPS)** | **Runtime secrets (ESO)** |
| --- | --- | --- |
| What | infra *config identifiers* | *credentials* a workload uses |
| Examples | account IDs, emails, state bucket/role, SSO endpoints | OAuth secrets, DB passwords, Slack/PagerDuty/GitHub-App tokens |
| Home | committed `infra/live/aws/secrets.enc.yaml` (KMS-sealed) | AWS Secrets Manager → synced k8s Secret |
| Read when | Terragrunt config-load (before providers) | runtime, in-cluster |
| Credentials? | **no** (identifiers only) | **yes** |
| ADR | [066](../../adrs/066-sops-encrypted-config-secrets.md) | [019](../../adrs/019-external-secrets-operator.md) |

## Config-in-git — SOPS ([ADR-066](../../adrs/066-sops-encrypted-config-secrets.md), built+live)

- **File:** `infra/live/aws/secrets.enc.yaml` — SOPS-encrypted, **committed** (public repo). Keys:
  `account_ids`, `admin_email`/`account_emails`, `state_bucket`, `state_role_arn`, `cloudflare_zone_id`,
  `argocd_sso_*`, optional `keycloak_sso_*`. **No credentials.**
- **Decrypt:** `root.hcl` + `common.hcl` set `_secrets = yamldecode(sops_decrypt_file(...))` — **inline, in
  memory**, no CI fetch, no plaintext on disk. Exposed to units via `_base.hcl` →
  `include.base.locals.account_ids["platform"]` / `account_id` / `admin_email`. `_base.hcl` also
  cross-checks `env.hcl`'s account_id against the map and aborts on mismatch.
- **The KMS key = the ACL:** `platform-sops` (mgmt account, module `aws/sops-kms`, alias `alias/platform-sops`,
  pinned by `.sops.yaml`). Key *policy* grants: operators (SSO admin) Encrypt+Decrypt (to edit); the ARC
  runner Decrypt-only. Decrypt principals via **account-root + `aws:PrincipalArn` `ArnLike`** (survives role
  recreation across a rebuild, unlike a direct role-ARN principal). Every decrypt = a CloudTrail event.
  `prevent_destroy` (bootstrap-floor — destroying it bricks a rebuild).
- **Bootstrap escape:** `TG_SOPS_BOOTSTRAP=1` → reads a local plaintext `infra/live/aws/secrets.hcl`
  (gitignored; structure in `secrets.hcl.example`) — only for the true from-zero moment before the KMS key
  exists.
- **Edit:** `sops infra/live/aws/secrets.enc.yaml` (decrypts to `$EDITOR`, re-encrypts on save — needs an
  SSO-admin identity, not the decrypt-only runner).
- **Belongs here:** ✅ stable config identifiers. ❌ app secrets/credentials (→ ESO). ❌ **customer PII —
  never in git**, encrypted or not.

## Runtime secrets — ESO + Secrets Manager ([ADR-019](../../adrs/019-external-secrets-operator.md), built+live)

- **Source of truth:** AWS **Secrets Manager**. **Bridge:** the **External Secrets Operator** (chart
  `0.14.3`, module `external-secrets`, ns `external-secrets`). Rejected alternatives (ADR-019): secrets in
  TF state (couples rotation to apply; state readers see all), Sealed Secrets (per-cluster key, no cloud
  integration), Vault (a Tier-0 system to run).
- **`ClusterSecretStore`** (module `secret-stores`): `aws-secrets-manager` (SecretsManager) +
  `aws-secrets-manager-ssm` (Parameter Store, cheaper). **No `auth` block** — ESO authenticates as its own
  **Pod Identity** (ADR-047, migrated from IRSA #594); the bridge holds no secret. Live: both Valid/ReadWrite/Ready.
- **`ExternalSecret`** (per workload): `secretStoreRef` {name, kind: ClusterSecretStore} · `refreshInterval`
  (`1h` everywhere today) · `target.name` + `creationPolicy: Owner` · `data[]` (`secretKey` ← `remoteRef.key` +
  `property`) or `dataFrom`. ESO reads the remote → materializes a k8s Secret → pod consumes via `envFrom`.
  **If ESO is down, existing Secrets keep working**; only new syncs/rotations pause.
- **IAM (read-only):** the ESO role gets `secretsmanager:GetSecretValue`/`DescribeSecret`/`ListSecretVersionIds`
  scoped to `secret:platform/*` (live unit sets `secret_path_prefix = "platform"` — **module default is `*`,
  wide; the unit narrows it**). No write/delete.
- **Worked example (live, `SecretSynced`):** `keycloak-config` writes ArgoCD's OIDC client secret to
  `platform/keycloak/argocd-oidc` → an ExternalSecret (store `aws-secrets-manager`, remoteRef that key,
  refresh 1h, target `argocd-keycloak-oidc`) → the k8s Secret ArgoCD mounts. (Same shape: `grafana-oidc`,
  the two-key `keycloak-admin` blob.)
- **Naming:** `platform/<subsystem>/<name>` (e.g. `platform/keycloak/admin`, `platform/backstage/github-app`).
  **16 ExternalSecrets** live across 8 namespaces, all `SecretSynced`.

## The tenant paved road — ADR-070 (**designed, NOT built**)

[ADR-070](../../adrs/070-tenant-app-config-and-secrets.md), Proposed. The *designed* model: **config** (non-secret)
→ git on the claim `services.<svc>.config` → a ConfigMap; **secrets** → the store, claim holds only key
*names* → the Composition mints a per-environment ExternalSecret. Write path = **Backstage is the sole broker**
(`platctl secret set` calls the same API), Pod-Identity-scoped to `…/tenants/<team>/<product>/<stage>`, prod
writes gated (`release-approver`), a Kyverno backstop denies a team's ExternalSecret targeting another team's
path. **What's landed:** only the XRD schema reservation (`services.<svc>.config`/`.secrets`, flagged *"inert
until the paved road ships"*). No tenant ExternalSecret in `gitops/` today — a tenant gets **nothing**
runtime-secrets yet; the platform's own services use ESO extensively.

## Keyless-first (the goal)

| Concern | Keyless (preferred) | Stored secret (only if unavoidable) |
| --- | --- | --- |
| Pod → AWS | **Pod Identity** | — |
| CI → AWS | **GitHub OIDC** | — |
| Image signing | **keyless cosign** | — |
| 3rd-party tokens | — | Slack/PagerDuty/GitHub-App/DB → Secrets Manager |

ESO itself proves it — it reads the store via Pod Identity, so the secrets bridge has no secret of its own.

## Rotation — [ADR-094](../../adrs/094-secret-rotation-strategy.md) (**Proposed; mostly design**)

The hard half is solved (identity creds are keyless). The static residue (~26 secrets at `Rotation: null`)
sorts into **4 classes**:

| Class | Owns both sides? | Mechanism | Examples |
| --- | --- | --- | --- |
| **A** Terraform two-sided | yes (TF/CNPG) | `time_rotating` keeper on `random_password` + scheduled `apply` — rotates both sides in lockstep | Keycloak OIDC (archetype), Grafana admin, Backstage session, CNPG passwords |
| **B** external provider | no (3rd party) | native SM rotation where supported, else scheduled-manual + expiry alert | Tailscale, PagerDuty, GitHub App keys, Cloudflare |
| **C** keyless | n/a | **nothing to rotate — the goal; keep growing it** | Pod Identity, OIDC, cosign, SSO |
| **D** tenant | future | design rotation in day one (don't retrofit) | (rebuild-gated) |

- **3 shared primitives:** **Reloader** (restart a workload on secret change — the keystone that turns a
  cached-old-value outage into a hands-off event) · **rotation-age alerts** (`secret_age_days` → alert past a
  per-class max) · **refresh-interval tiers** (24h/1h/15m — ADR-024 defined, never wired).
- **One-owner guardrail:** exactly one owner per secret (TF *or* a rotation Lambda, never both — the top risk).
- **Not Vault** (deliberate): ESO + Secrets Manager + Pod Identity cover it; Vault = a new Tier-0 system;
  keyless-first shrinks the problem.
- **Status:** ADR-094 Proposed. **Reloader NOT deployed** (the only `reloader` in-tree is Alloy's disabled
  `configReloader`), **zero `aws_secretsmanager_secret_rotation`**, **no age metric** (the only secrets alerts are
  `ExternalSecret`/`ClusterSecretStore Ready=False` — sync-failures, not age), **refresh tiers unwired** (flat `1h`). A
  manual runbook covers ~4 secrets. Phase 1 (deploy the primitives) is authored-but-unbuilt; verify preprod
  first on unpark.

## Status ledger

- **LIVE:** keyless-everywhere (Pod Identity/OIDC/cosign); SOPS config-in-git; ESO + ClusterSecretStores +
  16 platform ExternalSecrets; IAM scoped to `platform/*`.
- **Designed / not built:** the **tenant** config/secrets paved road (ADR-070 — schema reserved, inert);
  **automated rotation** (ADR-094 — classification decided, primitives not deployed).
- **Doc-drift:** ADR-019 still says IRSA (now Pod Identity, #594); ADR-066 §5 says `sops` is in
  `.tool-versions` — it's in *neither* `.tool-versions` nor the runner image; Terragrunt decrypts via the
  in-process SOPS library (needs `kms:Decrypt`), and the `sops` CLI is only for *editing*.

## Gotchas

- **git vs store:** config identifier the IaC reads → SOPS; credential a workload uses → Secrets Manager +
  ExternalSecret. Never cross them.
- **Rotated secret didn't take:** ESO re-synced the Secret, but the pod cached the env var — restart it
  (Reloader will automate; today manual).
- **`SecretSyncedError`:** the `remoteRef.key` doesn't exist, or isn't under the IAM-scoped `platform/*`.
- **config-load fails to decrypt:** the running identity needs **`kms:Decrypt`** on `platform-sops` —
  Terragrunt decrypts in-process; the `sops` CLI is only for *editing*.
- **module default `*` vs unit `platform/*`:** the `external-secrets` module defaults to a wide `*` scope; the
  live unit narrows it — always set the prefix.

## Go deeper

Deep dives: [config-in-git (SOPS)](deep-dive-config-in-git.md) ·
[runtime secrets (ESO)](deep-dive-runtime-secrets.md) · [rotation & lifecycle](deep-dive-rotation.md).
Runbook: `docs/runbooks/secret-rotation.md`. Related: [Identity](../identity/orientation.md),
[Foundations → IaC](../foundations/deep-dive-infrastructure-as-code.md). External:
[SOPS](https://github.com/getsops/sops) · [External Secrets Operator](https://external-secrets.io/latest/) ·
[AWS Secrets Manager](https://docs.aws.amazon.com/secretsmanager/) ·
[EKS Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html).
