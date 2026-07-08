# Learn: Secrets & Config — orientation

How the platform handles the thing every system needs and every system gets wrong: secrets, and their
quieter cousin, config. The short version: it tries hard not to *have* long-lived secrets at all, and for
the few it can't avoid, it keeps two separate planes and never mixes them.

**Audience:** platform engineers, and any developer who's wondered where a password actually comes from.
**Before you start:** [Identity & access](../identity/orientation.md) — federation is how most secrets get
eliminated — and [Foundations](../foundations/deep-dive-infrastructure-as-code.md), the Terragrunt config
chain, both help. Know roughly what a Kubernetes Secret and an AWS IAM role are; we'll build the rest.

## The question

Grafana needs its OIDC client secret. Backstage needs a GitHub App key. The Keycloak database needs a
Postgres password. The Terragrunt config needs to know which AWS account is "preprod." Every one of those is
a sensitive value that has to come from somewhere, and "somewhere" is a security decision. Put it in the
wrong place — a git commit, a Terraform variable, a baked-in image — and you've created a credential that
leaks, never rotates, and shows up in five copies.

**Where does each sensitive value live, who can read it, how does a workload get it without ever holding a
long-lived key, and how does any of it rotate?**

## The one idea: the best secret is one that doesn't exist

It's a posture before it's a mechanism. Wherever a credential can be replaced by *federated identity* —
short-lived, tied to who you are, auto-revoked — it is. For the irreducible few that remain, the platform
keeps two separate planes: build-time config is sealed in git (SOPS), and runtime secrets live in a managed
vault (AWS Secrets Manager) and are synced to workloads by the External Secrets Operator. The two never
cross. Rotation follows from the same classification.

The three moves, in order of preference:

- **Eliminate it (best).** A workload reaching AWS uses EKS Pod Identity — a short-lived, per-pod credential
  tied to its ServiceAccount, no key anywhere. CI reaching AWS uses GitHub OIDC federation. Images are signed
  with keyless cosign. None of these is a secret you store, leak, or rotate, because it doesn't exist. This is
  the goal, and the platform keeps expanding the set.
- **Seal it in git (for config).** The handful of *identifiers* the Terragrunt config needs at plan/apply —
  which account is "preprod," the contact email, the state bucket — are SOPS-encrypted and committed. Config,
  not credentials.
- **Vault it and sync it (for the rest).** The runtime credentials you can't federate — an external SaaS
  token you didn't mint (Slack, PagerDuty), a database password — live in Secrets Manager, and the External
  Secrets Operator copies them into Kubernetes Secrets on a schedule.

> **Keys to a building.** The first choice is a keycard badge (federated identity): tied to who you are, no
> physical key to copy or lose, revoked the moment you leave. A few old locks can't take a badge; for those
> the platform issues physical keys, kept in a managed key cabinet (Secrets Manager), and a keymaster hands
> stamped copies to exactly the rooms that need them (ESO). The building's own blueprints — which plot it sits
> on, which utility account it bills to — are sealed in a tamper-proof envelope but filed in the open records
> room (SOPS in git: encrypted, but committed and reviewable). Where the metaphor breaks: a real building
> can't dissolve a lock into thin air; federation does exactly that, which is why "eliminate" beats every kind
> of key.

---

## Stop 1 — config in git: SOPS-sealed identifiers

The Terragrunt config chain needs a few sensitive *identifiers* at evaluation time, before any provider
assumes a role and before any workload exists: the AWS account ID per environment, contact/creation emails,
the state bucket and role, some SSO endpoints. On a public repo, committing those in plaintext is a
non-starter — but they're exactly what the IaC must read at plan/apply.

The answer ([ADR-066](../../adrs/066-sops-encrypted-config-secrets.md)): encrypt the file with
[SOPS](https://github.com/getsops/sops) and commit the *encrypted* form (`infra/live/aws/secrets.enc.yaml`),
decrypting it in memory at config-load via a dedicated KMS key (`platform-sops`). Terragrunt calls
`sops_decrypt_file` inline — no CI fetch step, no plaintext ever written to disk. The KMS key's policy is the
access list, so revoking access is a policy edit, and every decrypt is a CloudTrail event.

> *A sealed envelope in a public filing cabinet.* Everyone can see the envelope is filed there — versioned,
> diffable in PRs — but only a badge that opens the lock (a KMS-authorized identity) reads the contents, and
> you read them in place, never take a photocopy home.

Two things make this the right home for this class and the wrong one for anything else:

- **It's build-time config the IaC itself reads** — before providers, before a runtime secret store even
  exists. You can't pull it from Secrets Manager, because you're bootstrapping the system that *creates*
  Secrets Manager (chicken-and-egg). (There's a `TG_SOPS_BOOTSTRAP=1` escape to a local plaintext file for
  the true from-zero moment before the KMS key exists.)
- **It contains no credentials.** Account IDs, emails, endpoints — identifiers, not passwords. If you're
  reaching for SOPS to hand a running app a password, you're on the wrong plane; that's Stop 2. And
  SOPS-encrypting a value never makes git the right home for the wrong *class* of data: customer PII in git is
  a non-starter, encrypted or not.

The [config-in-git deep dive](deep-dive-config-in-git.md) covers the SOPS/KMS mechanism, the
key-policy-as-ACL, and the bootstrap escape.

---

## Stop 2 — runtime secrets: Secrets Manager + the External Secrets Operator

Now the credentials a *running workload* needs — OAuth client secrets, DB passwords, third-party tokens. A
Kubernetes `Secret` is just base64 in etcd; the security question is where it comes from. Git, even
SOPS-sealed, is the wrong home for a *rotating* credential: to change it you'd re-encrypt and re-commit, and
the ciphertext is copied everywhere the repo is.

The answer ([ADR-019](../../adrs/019-external-secrets-operator.md)): AWS Secrets Manager is the source of
truth, and the External Secrets Operator (ESO) syncs a named secret out of it into a normal Kubernetes Secret
that any pod mounts unmodified. Two small pieces:

- A **`ClusterSecretStore`** — the connection to the vault (`aws-secrets-manager`), authenticated as ESO's own
  Pod Identity, so the secrets bridge itself holds no secret: it reads Secrets Manager as its ServiceAccount.
- An **`ExternalSecret`** per workload — "sync `platform/keycloak/argocd-oidc` from the store into a k8s Secret
  named `argocd-keycloak-oidc`, refreshed hourly." ESO materializes it; the pod consumes it via `envFrom` like
  any other Secret.

> *A bank safe-deposit box and a courier.* The credential lives once in the access-controlled, audited box
> (Secrets Manager); ESO is the courier who fetches a *copy* on a schedule and leaves it where the pod expects
> it — the pod never needs the vault key. Rotate the value in the box and the courier re-delivers; no redeploy.

This is live and carrying real load: 16 ExternalSecrets sync today across Backstage, Grafana/observability,
ArgoCD, Keycloak, the triage agent, and more — all `SecretSynced`. Access is bounded by ESO's IAM being scoped
to the `platform/*` name prefix — it can read only platform secrets. (Per-team tenant secret paths with a
Kyverno cross-tenant backstop are part of the designed tenant road below, not yet built.) Naming is
`platform/<subsystem>/<name>`.

**The honest caveat:** the platform's own services use this heavily, but the tenant self-service paved road —
a developer setting an app's secrets through Backstage and having the Environment claim wire the ExternalSecret
automatically ([ADR-070](../../adrs/070-tenant-app-config-and-secrets.md)) — is designed, not built. Today only
the claim's `config`/`secrets` schema is reserved (inert); the write-through API and per-tenant wiring are a
deferred phase. The [runtime-secrets deep dive](deep-dive-runtime-secrets.md) walks the mechanism, a worked
example, and that designed tenant road.

---

## Stop 3 — rotation: by class, not by timer

A secret that never rotates is a standing risk. But naïvely rotating everything on a timer is worse — a
rotated secret a running pod cached becomes an outage. So rotation is classification-driven
([ADR-094](../../adrs/094-secret-rotation-strategy.md)), and the hard half is already solved: most credentials
are keyless (the *eliminate* move), so there's nothing to rotate. What remains is a bounded set of static
values, sorted into four classes:

- **Class A — Terraform two-sided:** Terraform controls both the credential and its consumer — the archetype
  is a Keycloak OIDC client secret Terraform sets on the client *and* writes to the store. Rotate by re-apply;
  one apply changes both sides in lockstep. Most platform secrets are Class A, and rotating them is nearly
  free.
- **Class B — external provider:** a token a third party minted (Tailscale, PagerDuty, a GitHub App key). Some
  have a rotate-API; the rest are scheduled-manual with expiry alerting.
- **Class C — keyless:** nothing to rotate. The best class, and the strategy is to keep growing it.
- **Class D — tenant:** don't exist yet; design rotation in from day one, don't retrofit.

Three shared primitives make it hands-off: **Reloader** (restart a workload when its secret changes, so it
actually uses the new value — the keystone), **rotation-age alerts** (flag a secret that's too old), and
**refresh-interval tiers** (get a rotated value into the cluster fast). And one hard rule: exactly one owner
per secret — never let Terraform and a rotation Lambda fight over the same value.

> *Changing the locks.* Re-keying isn't just cutting a new key — it's cutting the new key *and* handing it to
> every tenant at the same moment, or you've locked people out. Reloader is that simultaneous hand-off.

**The honest status: this is mostly a design.** ADR-094 is Proposed; today rotation is a classification plus a
manual runbook for a handful of secrets. Reloader isn't deployed, there's no age metric, the refresh tiers
aren't wired — an authored-but-not-yet-built next phase. And, deliberately, no Vault: ESO, Secrets Manager, and
Pod Identity already cover it, and keyless-first keeps shrinking the problem, so a whole new Tier-0 secrets
engine isn't worth its operational cost. The [rotation deep dive](deep-dive-rotation.md) is careful about
exactly this line.

---

## The honest status — what's live vs designed

- **Live and in use:** keyless-everywhere (Pod Identity, OIDC, cosign — the eliminated majority); SOPS
  config-in-git (the platform's bootstrap identifiers); ESO + Secrets Manager for the platform's own runtime
  secrets (16 ExternalSecrets syncing).
- **Designed, not built:** the tenant config/secrets self-service paved road (ADR-070 — only the schema is
  reserved); automated rotation (ADR-094 — the classification is decided, the primitives aren't deployed).

The through-line holds either way: have fewer secrets, keep the ones you must on two clean planes, and never
let a rotating credential end up somewhere it can't rotate.

## When it breaks — the ones you'll actually hit

- **"Where do I put this value — git or the store?"** Is it a *config identifier* the IaC reads at plan/apply
  (account ID, email, endpoint)? SOPS in git. Is it a *credential a running workload uses*? Secrets Manager +
  an ExternalSecret. Never a credential in git; never an app secret in SOPS.
- **"My rotated secret didn't take effect."** ESO re-synced the k8s Secret, but the pod cached the old value in
  an env var — it needs a restart. (Reloader will automate this; today it's manual.)
- **"My ExternalSecret says `SecretSyncedError`."** Usually the secret name/path doesn't exist in Secrets
  Manager, or ESO's IAM isn't scoped to that prefix — check the `remoteRef.key` and that it's under
  `platform/*`.
- **"`terragrunt` fails at config-load with a decrypt error."** The running identity needs `kms:Decrypt` on the
  `platform-sops` key. Terragrunt's `sops_decrypt_file` decrypts *in-process*, so no `sops` CLI is needed to
  read; the `sops` binary is only for *editing* the file. The CI runner has the grant.

## Go deeper

- [Config in git (SOPS)](deep-dive-config-in-git.md) — the SOPS/KMS mechanism, the key-policy-as-ACL, the
  bootstrap escape, and the SOPS-vs-ESO boundary.
- [Runtime secrets (ESO + Secrets Manager)](deep-dive-runtime-secrets.md) — the ClusterSecretStore +
  ExternalSecret mechanism, a worked example, naming/scoping, keyless-first, and the designed tenant road.
- [Rotation & lifecycle](deep-dive-rotation.md) — the classification, the three primitives, the one-owner
  guardrail, the not-Vault decision, and the honest built-vs-designed status.
- The lookup: the [Reference](reference.md). Related: [Identity & access](../identity/orientation.md),
  [Foundations → IaC](../foundations/deep-dive-infrastructure-as-code.md).
