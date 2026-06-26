# ADR-066: SOPS-Encrypted Config Secrets in Git (KMS)

**Date:** 2026-06-10

**Status:** Accepted — built + live (secrets.enc.yaml committed, #338–342)

## Context

Terragrunt's config chain reads a single file of environment-identifying values at evaluation time —
`infra/live/aws/secrets.hcl`, loaded by `common.hcl`:

```hcl
_secrets = read_terragrunt_config("${get_repo_root()}/infra/live/aws/secrets.hcl")
```

It holds **account IDs** (mgmt/platform/preprod/prod/test), **account emails** + `admin_email`,
**SSO URLs + CA data** (argocd/keycloak — mostly for optional upstream federation), the **cloudflare
zone id**, and the **state bucket + `TerraformStateAccess` role ARN**. Notably it contains **no actual
credentials** — no passwords, keys, or tokens; real secrets live in AWS Secrets Manager and are pulled
by External Secrets. It is gitignored as a *"don't commit the org's account IDs / emails"* posture, and
**this is a public repository**, so committing it in plaintext is not an option.

Until now this was invisible: every operator has the file on their laptop (from `secrets.hcl.example`),
and **no CI ever ran Terragrunt against a live unit** — `ci.yml` only `tofu validate`s modules, and the
tenant-claims gate does schema checks. The CI apply-on-merge work (ADR-065 self-hosted runners; #305
Phase 1) changes that: a fresh runner checkout has **no `secrets.hcl`**, so `terragrunt plan/apply` fails
at config load (`read_terragrunt_config ... folder does not contain a terragrunt.hcl file`). We need a
way to get this config to CI that is **safe for a public repo** and doesn't fork into a second,
drift-prone copy.

### Alternatives Considered

**1. Keep it gitignored; materialize it in CI from a store (AWS Secrets Manager / GitHub Actions
secret).** A CI step fetches the file contents and writes `secrets.hcl` before Terragrunt runs.
Rejected as the primary design: it creates a **second copy** of the file that silently **drifts** from
each operator's local one — every edit must be made in two places, and a stale store yields a CI apply
that diverges from what an operator would do. It also writes plaintext to the runner's disk. (This was
the first instinct; the drift problem is disqualifying.)

**2. Commit it in plaintext.** Simplest, single source, zero drift — but the repo is **public**.
Committing account IDs + org emails + SSO endpoints is not acceptable. Rejected.

**3. Reconstruct it in CI from discoverable values.** Account IDs are discoverable
(`aws organizations list-accounts`), state bucket/role are constructible. But the emails and SSO
URLs/CA are not derivable, and any unit that grows a new key silently breaks. Brittle. Rejected.

**4. SOPS-encrypted file committed to git, decrypted via AWS KMS (chosen).** Encrypt the config with
[SOPS](https://github.com/getsops/sops) per-value and **commit the encrypted file**. Because it's
encrypted, committing it to a public repo is safe; because it's *in git*, it is the **single source of
truth — no second copy, no drift.** Terragrunt has a built-in `sops_decrypt_file` function, so
`common.hcl` decrypts it **inline at config-eval time** — no CI fetch step, and **no plaintext ever
written to disk**, on the runner or on a laptop. Decryption is gated by **KMS key policy + IAM**, which
operators and the runner already have identities for, and every decrypt is logged in CloudTrail.

### Master-key choice: KMS vs. age

SOPS supports AWS KMS, GCP KMS, Azure Key Vault, PGP, and `age`. We choose **AWS KMS**: every principal
that needs to decrypt (SSO operators, the ARC runner role) **already has an AWS identity**, so access is
expressed as a KMS key policy with no key material to distribute. `age` is simpler but reintroduces a
secret-distribution problem (every operator + the runner needs the age private key) — the exact thing
KMS+IAM avoids on an AWS-native platform. KMS also gives CloudTrail decrypt audit. (`age` recipients may
be added later as a break-glass path, but KMS is the primary.)

## Decision

Adopt **SOPS-encrypted config, committed to git, decrypted via a dedicated AWS KMS key**, read inline by
Terragrunt.

1. **`infra/live/aws/secrets.enc.yaml`** (SOPS-encrypted, **committed**) replaces the gitignored
   `secrets.hcl`. The data is expressed as **YAML** (so SOPS encrypts per-value and Terragrunt can
   `yamldecode` it) — same keys, new format. The decrypted form is never committed; operators edit via
   `sops infra/live/aws/secrets.enc.yaml`, which opens the plaintext in `$EDITOR` and re-encrypts on save.

2. **`common.hcl`** decrypts inline:

   ```hcl
   _secrets = yamldecode(sops_decrypt_file("${get_repo_root()}/infra/live/aws/secrets.enc.yaml"))
   ```

   (Field access drops the `.locals` hop — `local._secrets.account_ids` instead of
   `local._secrets.locals.account_ids`.)

3. **A dedicated SOPS KMS key.** A new, single-purpose CMK (alias `alias/platform-sops`) encrypts the
   config. `.sops.yaml` at the repo root pins the creation rule (path regex → this key ARN) so new
   encryptions use it automatically.

4. **Key policy = who may decrypt.** Decryption happens with the **ambient** identity at config-eval
   time (before any provider assume-role), so the key policy grants `kms:Decrypt` to: the **SSO
   AdministratorAccess** roles (operators, via an `ArnLike` like PlatformDeployer's) and the **ARC runner
   role** (`*-arc-runner`). Operators additionally get `kms:Encrypt`/`GenerateDataKey` for editing. The
   runner needs decrypt only.

5. **`sops` in the toolchain.** Pinned in `/.tool-versions`, baked into the `platform/gha-runner` image,
   and installed by operators (`mise install`).

6. **Bootstrap ordering (the chicken-and-egg).** The SOPS KMS key cannot be created by a normal unit,
   because *every* unit's config load now decrypts `secrets.enc.yaml`, which needs the key. So the key is
   **bootstrap-tier**, created before/outside the secrets-reading flow — the same pattern as the S3 state
   backend (ADR-006 `state_bootstrap`): a tiny unit/script that does not load `common.hcl`, run once. The
   key is then a standing prerequisite, like the state bucket.

7. **Migration.** One-time: create the key, `sops -e` the current `secrets.hcl` → `secrets.enc.yaml`,
   switch `common.hcl`, delete `secrets.hcl` from the gitignore set (replace with a note), refresh
   `secrets.hcl.example` → a `secrets.enc.yaml` schema doc + the `sops` edit instructions. Operators
   install `sops` and confirm KMS decrypt; the runner role gets the decrypt grant (ARC module).

## Consequences

### Positive

- **Single source of truth, zero drift.** The config lives in git (encrypted); there is no second copy
  to keep in sync. CI and every operator read the exact same bytes.
- **Public-repo safe.** Only the KMS-encrypted form is committed.
- **No plaintext on disk.** Terragrunt decrypts inline via `sops_decrypt_file`; nothing is written —
  on the runner or a laptop.
- **IAM-gated + audited.** Access is a KMS key policy; every decrypt is a CloudTrail `Decrypt` event.
  Revoking an operator or the runner is a policy edit, not a re-distribution.
- **Unblocks all CI applies.** Phase 1 (teams) *and* Phase 2 — any runner `terragrunt` run can now load
  config. This ADR is a prerequisite for #305.
- **Standard, portable pattern.** SOPS + KMS for encrypted IaC config in git is well-trodden.

### Negative

- **A migration touching every operator.** Everyone moves from a plaintext file to `sops` + KMS decrypt.
  Bounded and one-time, but it changes the local workflow and needs a clear runbook.
- **A new bootstrap-tier dependency.** The SOPS KMS key joins the state backend as a thing that must
  exist before anything else (and must survive teardown, or be re-bootstrapped first). The teardown/
  rebuild runbook must account for it.
- **Editing requires the tool.** You can no longer just open `secrets.hcl`; you `sops` the encrypted
  file. Standard SOPS UX, but a habit change, and a malformed edit fails the encrypt.
- **YAML format change.** The config moves HCL→YAML; the `common.hcl` accessors change shape
  (`_secrets.x` vs `_secrets.locals.x`). A small, mechanical edit, but it touches the config root.
- **KMS coupling at config-eval.** Every Terragrunt invocation now makes a KMS `Decrypt` call (fast,
  but a hard dependency on KMS availability + the caller having decrypt). Acceptable; KMS is already in
  the critical path (EBS/EKS/state encryption).

## References

- ADR-065 (self-hosted ARC runners — the CI applies that exposed this gap)
- ADR-006 (S3 state bootstrap — the analogous bootstrap-tier "exists before everything" pattern)
- #305 (Terragrunt-in-CI; blocked on this)
- SOPS: <https://github.com/getsops/sops> · Terragrunt `sops_decrypt_file`
