# Learn: Secrets & Config — config in git (deep dive)

> Assumes the [Secrets & Config orientation](orientation.md) — specifically **Stop 1**, the
> *sealed-envelope-in-a-public-filing-cabinet* idea. That gave you the shape: the Terragrunt config chain
> needs a handful of *identifiers* at evaluation time, they can't be plaintext in a public repo, so they're
> **SOPS-encrypted and committed** and decrypted in memory. This deep dive opens the envelope and shows the
> machine: the exact file, the decrypt chain, the KMS key policy *as* the access-control list, the one ARN
> trick that keeps a rebuild from bricking CI, and the from-zero escape hatch. One area, in depth.
> Already fluent in SOPS + KMS key policies? The [reference](reference.md) is the terse lookup.

Callback to the metaphor, because we'll lean on it: the envelope is **filed in the open** (committed,
versioned, diffable), but its *contents* are sealed, and you only read them **in place** — a KMS-authorized
identity decrypts into memory and nothing is ever photocopied to disk. Where the metaphor gains a wrinkle
the orientation skipped: the *lock on the envelope* is an AWS KMS key, and that lock's **policy** is the
whole security story. Get the lock's wiring subtly wrong and either nobody can open the envelope, or a
routine teardown/rebuild jams the lock permanently. That wiring is what this doc is about.

## The file: `infra/live/aws/secrets.enc.yaml`

One file, committed to a **public** repository, holding YAML where every *value* is a
`ENC[AES256_GCM,data:…,iv:…,tag:…,type:str]` blob. The keys are readable; the values are not. Here's the top
of the real committed file (values are genuinely encrypted — this is what `git show` prints):

```yaml
account_emails:
    platform: ENC[AES256_GCM,data:tTcqW65J…,iv:ekW29SD/…,tag:Q9gJ3g6L…,type:str]
    preprod: ENC[AES256_GCM,data:B1gWxAKX…,iv:B49+zYEU…,tag:s9sRMHCz…,type:str]
account_ids:
    mgmt: ENC[AES256_GCM,data:if/xxhNN…,iv:3PEX3VLH…,tag:aeCUxcA5…,type:str]
    platform: ENC[AES256_GCM,data:8buQRHB7…,iv:gAu8bJ/o…,tag:ESTMk5Yp…,type:str]
```

What's under the seal, per the schema in
[`secrets.hcl.example`](https://github.com/asanexample/platform/blob/main/infra/live/aws/secrets.hcl.example)
and the accessors in
[`common.hcl`](https://github.com/asanexample/platform/blob/main/infra/live/aws/common.hcl):

- **`account_ids`** — the AWS account number per environment (`mgmt`/`platform`/`preprod`/`prod`/`test`).
- **`admin_email`** and **`account_emails`** — the contact email (Let's Encrypt, CAA records) and the
  per-account Organizations creation emails.
- **`state_bucket`** and **`state_role_arn`** — the S3 state bucket and the `TerraformStateAccess` role ARN.
- **`cloudflare_zone_id`** — the DNS zone ID.
- **`argocd_sso_url`** / **`argocd_sso_ca_data`**, and *optional* **`keycloak_sso_*`** — SSO endpoints + a
  base64 SAML cert body, needed only when federating an upstream corporate IdP.

Read that list again with one lens: **every entry is an identifier, not a credential.** An account number
is a routing fact, not a password. A bucket name is a location. There is **no key, token, or password in
this file** — those live in AWS Secrets Manager and reach workloads through the External Secrets Operator
(the other plane; [runtime-secrets deep dive](deep-dive-runtime-secrets.md)). This is the single most
important boundary in the whole subsystem, and we'll return to it at the end. The reason it's *encrypted* at
all isn't that identifiers are dangerous on their own — it's that a **public repo** shouldn't broadcast an
organization's account map and internal emails to every scraper on earth.

## Why committed-encrypted beats a runtime store — for *this* class

The orientation asserted this; here's the argument, because it's the crux of ADR-066. Four reasons, and
each maps to an alternative that was explicitly **rejected** in
[the ADR](../../adrs/066-sops-encrypted-config-secrets.md):

1. **It's build-time config the IaC reads *before* a secret store is reachable.** Terragrunt evaluates
   `secrets.enc.yaml` at *config-load* — before any provider assumes a role, before the S3 backend is even
   configured (the backend *bucket name itself* comes from this file). You cannot fetch it from Secrets
   Manager, because you may be bootstrapping the very account that *contains* Secrets Manager. Classic
   chicken-and-egg: the config that stands up the platform can't depend on the platform being up.
2. **Single source of truth = zero drift.** The rejected "materialize it in CI from a store" design creates
   a **second copy** — the store's copy and each operator's local copy — that silently diverge. The ADR
   calls that drift *"disqualifying"*: a stale store yields a CI apply that differs from what an operator
   would produce. In git, CI and every laptop read the exact same bytes.
3. **Versioned + PR-reviewable.** Because the ciphertext is committed, a change to it is a diff in a pull
   request. You can't read the values, but you *can* see that a value changed, when, and by whom — the same
   review surface as any other config.
4. **No plaintext ever on disk.** Terragrunt's built-in
   [`sops_decrypt_file`](https://terragrunt.gruntwork.io/docs/reference/built-in-functions/) decrypts
   **inline, in memory**. Nothing is written to the runner or your laptop — unlike a CI step that `echo`s a
   fetched file to disk before Terraform runs.

## The mechanism: how a value becomes `include.base.locals.account_id`

Three files carry a secret from ciphertext to a usable local. Trace one — `account_ids` — end to end.

**Step 1 — decrypt, twice, at the config root.** Both
[`root.hcl`](https://github.com/asanexample/platform/blob/main/infra/root.hcl) and
[`common.hcl`](https://github.com/asanexample/platform/blob/main/infra/live/aws/common.hcl) define
`_secrets` with the *same* conditional:

```hcl
_secrets = get_env("TG_SOPS_BOOTSTRAP", "") == "1"
  ? read_terragrunt_config("${get_repo_root()}/infra/live/aws/secrets.hcl").locals
  : yamldecode(sops_decrypt_file("${get_repo_root()}/infra/live/aws/secrets.enc.yaml"))
```

`root.hcl` needs it early: the **S3 remote-state backend** reads `local._secrets.state_bucket` and
`local._secrets.state_role_arn`. So even `terragrunt init` — before a single resource — has already
decrypted the envelope. `common.hcl` then flattens the map into named locals: `account_ids`, `admin_email`,
`account_emails`, `cloudflare_zone_id`, `argocd_sso_url`, and so on.

**Step 2 — re-expose through `_base.hcl`.** Units don't touch `common.hcl` directly; they `include` the
[`_base.hcl`](https://github.com/asanexample/platform/blob/main/infra/live/aws/_base.hcl) layer, which
re-publishes the flattened locals so a unit reads `include.base.locals.account_ids["platform"]` or
`include.base.locals.account_id` (the current env's).

**Step 3 — the safety check that makes a wrong account *fail loudly*.** `_base.hcl` also cross-checks the
per-env `account_id` from `env.hcl` against the decrypted `account_ids` map:

```hcl
_assert_account = (
  local._expected_account == null ||
  local._expected_account == local.env_vars.locals.account_id
  ? true
  : tobool("SAFETY: env '${local.env}' expects account '${local._expected_account}' but env.hcl has '…'")
)
```

`tobool("some string")` is a deliberate poison pill — it's not a real boolean, so OpenTofu **aborts config
evaluation** with that message. The envelope isn't just a data source; it's the *source of truth* a
mis-configured `env.hcl` gets validated against, so you can't apply preprod's config into the prod account
by fat-fingering a number.

## The KMS key *is* the access-control list

The lock on the envelope is a single-purpose customer-managed KMS key, `alias/platform-sops`, in the
**management** account. The [`.sops.yaml`](https://github.com/asanexample/platform/blob/main/.sops.yaml)
creation rule pins the file's `path_regex` to that key's ARN, so any new encryption automatically uses it —
you never pick a key by hand. The key is built by the
[`sops-kms` module](https://github.com/asanexample/platform/blob/main/infra/modules/aws/sops-kms/main.tf)
with **rotation enabled** and a `prevent_destroy` seatbelt (more on why below).

Who may open the envelope is **entirely** the key's resource policy — three statement classes:

- **`EnableRootAdmin`** — `kms:*` for the management account root, so key admins manage policy and rotation
  through normal IAM. Standard KMS hygiene.
- **`OperatorsEncryptDecrypt`** — SSO `AdministratorAccess` operators get encrypt **and** decrypt (plus
  `GenerateDataKey*`/`ReEncrypt*`/`DescribeKey`), because *editing* the file re-encrypts every value. Scoped
  to the SSO reserved-role pattern via an `aws:PrincipalArn` `ArnLike` condition, granted across the
  management, platform, **and** preprod account roots.
- **`DecryptOnly`** — the ARC CI runner role gets `kms:Decrypt` + `kms:DescribeKey` and nothing else. It
  *reads* config on every apply; it never edits it.

Revoking access is therefore a **policy edit**, not a key rotation or a re-distribution — and every single
decrypt is a **CloudTrail `Decrypt` event**, so "who read the config, when" is auditable for free.

## The `ArnLike` trick: why principals are account-roots, not role ARNs

This is the subtle bit, and it's the kind of thing that bites you six months later during a rebuild. Look
at how `DecryptOnly` names its principal — **not** the runner's role ARN directly, but the runner's
*account root* plus an `aws:PrincipalArn` condition that matches the role ARN:

```hcl
principals { type = "AWS", identifiers = local.decrypt_account_roots }  # arn:aws:iam::<acct>:root
condition { test = "ArnLike", variable = "aws:PrincipalArn", values = var.decrypt_principal_arns }
```

Why the indirection? Because **KMS resolves a role-ARN principal to the role's immutable unique-id at write
time.** If you wrote `Principal = <runner-role-ARN>` directly, KMS would silently store the role's internal
unique-id (`AROA…`). Then a teardown/rebuild that **recreates that role** — same name, same ARN, but a
*new* unique-id — would leave the key policy pointing at a unique-id that no longer exists. The grant is
orphaned, and **every CI config-decrypt breaks** until someone manually re-applies the key. The
`account-root + ArnLike` form instead matches on the **ARN string**, which is stable across recreation — so
the grant survives a rebuild with no re-apply. Both the operator and decrypt statements use this posture
deliberately; the module comment spells it out. It's the same reason the platform's other cross-account
trust policies (PlatformDeployer) match by ARN pattern, not by principal.

> The envelope's lock is keyed to *"anyone holding a badge shaped like `…/arc-runner`"*, not to *"badge
> serial #4471"*. Re-issue the badge with the same shape and it still opens the lock. Where the metaphor
> breaks: a physical lock can't tell badge shape from serial — KMS very much can, and picking the wrong one
> is invisible until the day you re-issue.

## Cross-account decrypt needs *both* sides

The runner lives in the **platform** account; the key lives in **management**. Cross-account KMS is a
two-key handshake — admitting the caller in the key policy is necessary but **not sufficient**:

- **Resource side** — the `DecryptOnly` statement admits the runner (above).
- **Identity side** — the runner's own IAM must *also* grant `kms:Decrypt`. In the
  [ARC module](https://github.com/asanexample/platform/blob/main/infra/modules/actions-runner-controller/main.tf)
  the `DecryptSopsConfig` statement does exactly that, scoped to the key **by alias** with a
  `kms:ResourceAliases` condition — so it's a decrypt right on *the `platform-sops` key specifically*, not a
  blanket decrypt over all of management's keys.

Miss either side and the runner gets `AccessDenied` at config-load. This is a common cross-account KMS
gotcha; the platform's answer is "both, scoped as tightly as possible on each side."

## The bootstrap escape: `TG_SOPS_BOOTSTRAP=1`

There's a genuine chicken-and-egg at the very beginning: `platform-sops` is itself created by a Terragrunt
unit, and *that* unit's config load would try to decrypt `secrets.enc.yaml` with a key that doesn't exist
yet. The escape is the first branch of the `_secrets` conditional: set `TG_SOPS_BOOTSTRAP=1` and Terragrunt
reads a **local plaintext**
[`secrets.hcl`](https://github.com/asanexample/platform/blob/main/infra/live/aws/secrets.hcl.example)
instead — gitignored (`**/secrets.hcl`), never committed.

Three things make this safe rather than a backdoor:

- **Both branches yield the same flat map.** The HCL file's `.locals` and the YAML's `yamldecode` produce
  identical shapes, so `local._secrets.account_ids` is byte-identical either way — no accessor changes.
- **Terragrunt short-circuits the conditional**, so the *un-taken* branch's file is never even read. On a
  normal apply, `secrets.hcl` doesn't need to exist.
- **It's needed only from-zero**, before `platform-sops` exists. After bootstrap, `secrets.hcl` is kept
  locally as a **DR copy and the re-encryption source** (edit it, `sops -e` back to `secrets.enc.yaml`).

This mirrors `root.hcl`'s other escape, `TG_FORCE_DEPLOYER=1` — same pattern: a default-off env flag that
swaps behavior for a bootstrap edge case, byte-identical for the normal operator path.

## The boundary that decides everything: SOPS vs. ESO

Say it once more because it's the rule you'll reach for wrong: **SOPS holds infra config the IaC reads at
plan/apply; the External Secrets Operator hands a *running workload* the credentials it consumes.** If
you're reaching for `secrets.enc.yaml` to give a running app a database password or an OAuth client secret,
you're on the wrong plane — that value belongs in Secrets Manager with an `ExternalSecret`. And no amount
of SOPS-encryption makes git the right home for the *wrong class* of data: **customer PII never goes in git,
encrypted or not.** SOPS answers "which account is preprod?"; it must never answer "what's the password?"

## Gotchas that teach

- **The `sops` binary is *not* how CI decrypts — and it's not where the ADR says it is.** ADR-066 §5 claims
  `sops` is pinned in `/.tool-versions`, baked into the `gha-runner` image, and installed by `mise install`.
  Verified against primary source, **none of the automated-install claims hold**: `sops` is absent from
  [`.tool-versions`](https://github.com/asanexample/platform/blob/main/.tool-versions) *and* from the
  [gha-runner Dockerfile](https://github.com/asanexample/platform/blob/main/docker/gha-runner/Dockerfile)
  (which bakes tofu/terragrunt/kubectl/helm/awscli only). Yet CI applies decrypt config fine — because
  `sops_decrypt_file` is a **Terragrunt built-in** that decrypts **in-process** using the SOPS Go library.
  It shells out to *nothing*; it needs `kms:Decrypt`, not the CLI. The `sops` **binary** is required only to
  **edit** the file (`sops infra/live/aws/secrets.enc.yaml`, which re-encrypts on save). So a local operator
  who ran `mise install` and expected `sops` would **not have it** — a real doc-drift worth filing against
  the ADR.
- **`prevent_destroy` + teardown tooling must exclude this unit.** The key encrypts the *committed* file, so
  destroying `platform-sops` makes `secrets.enc.yaml` **permanently undecryptable** and bricks any rebuild.
  `prevent_destroy` is the seatbelt in the module, but it's belt-*and*-suspenders: `platctl` teardown must
  also skip the unit, exactly like the S3 state backend (ADR-006). This is a **bootstrap-floor** resource.
- **The preprod operator grant is load-bearing, not symmetry.** You might read the three operator accounts
  (mgmt/platform/preprod) as tidy uniformity. It's not: the bootstrap-tier `preprod/iam-roles` unit runs
  **account-direct** (it predates `PlatformDeployer`, so it can't assume the management base role) and it
  decrypts `secrets.enc.yaml` at config-eval. Drop the preprod grant and a from-scratch rebuild fails on
  preprod.
- **Editing needs an SSO-admin identity, not the runner.** The runner is decrypt-only by design, so it
  physically *cannot* re-encrypt. Editing the envelope is an operator action (`OperatorsEncryptDecrypt`).
- **What belongs, sharply.** *Yes:* config identifiers (accounts, emails, endpoints, bucket/role, zone).
  *No:* application secrets → that's ESO + Secrets Manager. *Never:* customer PII, in any form.

## Go deeper

- **Source of truth:** [ADR-066](../../adrs/066-sops-encrypted-config-secrets.md) (the decision + rejected
  alternatives, incl. the *drift is disqualifying* argument and the KMS-vs-age choice); ADR-006 (the S3
  state bootstrap — the analogous "exists before everything" floor).
- **The code:**
  [`sops-kms` module](https://github.com/asanexample/platform/blob/main/infra/modules/aws/sops-kms/main.tf)
  (the three statement classes + the `ArnLike` comment),
  [its live unit](https://github.com/asanexample/platform/blob/main/infra/live/aws/mgmt/global/sops-kms/terragrunt.hcl)
  (operator/decrypt principals, the preprod note),
  [`root.hcl`](https://github.com/asanexample/platform/blob/main/infra/root.hcl) +
  [`common.hcl`](https://github.com/asanexample/platform/blob/main/infra/live/aws/common.hcl) +
  [`_base.hcl`](https://github.com/asanexample/platform/blob/main/infra/live/aws/_base.hcl) (the decrypt →
  flatten → re-expose → safety-check chain).
- **External substrate** (each verified reachable):
  - [SOPS](https://github.com/getsops/sops) — the tool and file format; the `getsops/sops` maintainer repo.
    ~10 min for the README's KMS section.
  - [Terragrunt `sops_decrypt_file`](https://terragrunt.gruntwork.io/docs/reference/built-in-functions/) —
    the built-in that does the in-process decrypt (Terragrunt v1.x docs, matching our v1.0.7). ~2 min.
  - [AWS KMS key policies](https://docs.aws.amazon.com/kms/latest/developerguide/key-policies.html) and
    [ABAC / `kms:ResourceAliases`](https://docs.aws.amazon.com/kms/latest/developerguide/abac.html) — why
    the alias-scoped identity grant works. ~15 min for both.
- **The other plane:** [runtime secrets (ESO + Secrets Manager)](deep-dive-runtime-secrets.md) and the
  [rotation deep dive](deep-dive-rotation.md); back up to the [orientation](orientation.md).
