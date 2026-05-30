# Runbook — The Test Sandbox Account (`157263244316`)

How the **Test** AWS account is set up, why it's deliberately minimal, how to get access, and how to
apply its (small) IaC. Companion to the [IAM roles](../../CLAUDE.md#iam-roles) and
[GitHub OIDC](../adrs/036-github-actions-oidc-federation.md) docs.

---

## 1. What it is

| | |
|---|---|
| **Account ID** | `157263244316` |
| **Name / email** | `Test` / `josh+test@deeden.org` |
| **Purpose** | Isolated, disposable sandbox where **Terratest** (Go integration tests in `infra/tests/aws/`) creates and destroys *real* AWS resources, blast-radius-isolated from platform/preprod/prod. |
| **Persistent resources** | Just the GitHub OIDC provider + one role, `github-actions-terratest` (AdministratorAccess, assumable only via OIDC from `asanexample/platform` CI on `main`/`feat/*`). Defined by `infra/live/aws/test/global/github-oidc/`. |
| **What it does NOT have** | No `PlatformDeployer`, no `PlatformAdmin`, no in-account Terraform state. It is intentionally *not* a full fleet account. |

## 2. Architecture decision — keep it minimal (no `PlatformDeployer`)

**Decision (2026-05-29):** the Test account stays minimal — we do **not** bootstrap the standard
`PlatformDeployer` role here.

**Why:**

- **Least standing privilege (ADR-040).** `PlatformDeployer` is a *standing* privileged role assumable
  by a human deployer. The account already has exactly one admin-capable role (`github-actions-terratest`),
  and that one is constrained to transient OIDC assumption by CI. A second broad standing role buys
  nothing here.
- **The account should stay empty.** Bootstrapping `PlatformDeployer` properly would mean adding the
  `iam_roles` / `state_bootstrap` units to the test env — real surface area for an account whose whole
  job is to be disposable.
- **Its IaC changes ~never.** The only persistent unit (`github-oidc`) changes only on events like a
  GitHub org rename. That doesn't justify a permanent privileged role.

**Consequence:** Terragrunt applies for this account run **in-account** (as your SSO `AdministratorAccess`),
not via the usual `AWS_PROFILE=management` → assume-`PlatformDeployer` path. `infra/root.hcl` already
supports this natively — see §4.

## 3. Granting human (SSO) access

The Test account is in the org but, by default, no SSO permission set is assigned to it. To grant
yourself access:

1. **IAM Identity Center** (management account, `us-east-1`) → **AWS accounts** → select **Test
   (`157263244316`)** → **Assign users or groups**.
2. **Groups** tab → select **Admins** ("Full administrator access to all accounts") → **Next**.
3. Permission set → **AdministratorAccess** → **Submit**. (Provisions in a few seconds.)

Then add a local profile (already present in this repo author's `~/.aws/config`; replicate if missing):

```ini
[profile test]
sso_session = management
sso_account_id = 157263244316
sso_role_name = AdministratorAccess
region = us-east-1
```

Verify:

```bash
aws sso login --profile test          # only if the cached SSO session predates the assignment
aws sts get-caller-identity --profile test   # → 157263244316
```

## 4. How Terragrunt applies work here (in-account)

`infra/root.hcl` generates the `aws` provider conditionally:

```hcl
aws_assume_role = local.aws_account_id != "" ? local.aws_account_id != get_aws_account_id() : false
# assume PlatformDeployer ONLY when the target account != the caller's account
```

So when you apply **from inside the Test account** (`AWS_PROFILE=test`, caller = `157263244316`,
target = `157263244316`), `aws_assume_role = false` → the provider uses your ambient SSO-admin creds
directly and **never tries to assume `PlatformDeployer`**. (Running with `AWS_PROFILE=management`
instead would make it try to assume the non-existent `PlatformDeployer` → 403. Don't.)

> **The one catch — shared Terraform state.** The S3 state bucket + DynamoDB lock table live in the
> **management** account, reached via the `TerraformStateAccess` role. That role's trust currently lists
> only **platform / management / preprod** account roots — **not** the Test account. So a `terragrunt
> plan/apply` from `AWS_PROFILE=test` succeeds on the provider but **fails at backend init** ("not
> authorized to assume `…:role/TerraformStateAccess`"). Enabling it is §5.

## 5. Enabling state access (required before any apply) — the secure way

`TerraformStateAccess` grants **read/write/delete on the *entire* state bucket** (all envs' state). So
we must **not** add the Test account as a bare `:root` principal — that would let
`github-actions-terratest` (AdministratorAccess, OIDC-assumable by CI) reach and even delete all state.

Instead, add the Test account with a **trust condition scoped to the SSO admin role only** (excludes the
CI role). The `iam_roles` module supports `trust_conditions`. Edit
`infra/live/aws/mgmt/global/state-access/terragrunt.hcl`:

```hcl
TerraformStateAccess = {
  trust_principals = {
    aws = [
      "arn:aws:iam::${...["platform"]}:root",
      "arn:aws:iam::${...["mgmt"]}:root",
      "arn:aws:iam::${...["preprod"]}:root",
      "arn:aws:iam::157263244316:root",            # + Test account
    ]
  }
  # Restrict the Test-account principal to the human SSO admin — NOT the github-actions-terratest CI
  # role — so CI can never reach shared state. (The other accounts are gated by which principals they
  # grant sts:AssumeRole to; the Test account's only other privileged principal is the CI role, hence
  # this explicit condition.)
  trust_conditions = [{
    test     = "StringLike"
    variable = "aws:PrincipalArn"
    values   = [
      "arn:aws:iam::157263244316:role/aws-reserved/sso.amazonaws.com/*AdministratorAccess*",
      # keep the existing accounts unconditioned by NOT scoping them — see note below
    ]
  }]
}
```

> **Note:** a single `trust_conditions` block applies to the *whole* trust statement. If you only want to
> condition the Test principal (and leave platform/mgmt/preprod unconditioned), split it into a second
> role-statement or model the Test grant as a separate role. Simplest correct approach: a dedicated
> `TerraformStateAccessTest` role trusting `157263244316:root` **with** the SSO-admin condition, and
> point only the test env's backend at it. Decide this when you actually wire Terratest CI; it's a
> deliberate state-access design step, not a rubber-stamp.

Apply the state-access change from management (caller = mgmt, target = mgmt → no assume needed):

```bash
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
cd infra/live/aws/mgmt/global/state-access
AWS_PROFILE=management terragrunt plan -out=tfplan.bin && AWS_PROFILE=management terragrunt apply tfplan.bin
```

## 6. Applying the test `github-oidc` unit

Once §5 is done, apply in-account:

```bash
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
cd infra/live/aws/test/global/github-oidc
AWS_PROFILE=test terragrunt plan -out=tfplan.bin    # expect: 2 trust-policy sub changes, 0 destroy
AWS_PROFILE=test terragrunt apply tfplan.bin
```

Verify the live trust flipped:

```bash
AWS_PROFILE=test aws iam get-role --role-name github-actions-terratest \
  --query 'Role.AssumeRolePolicyDocument' --output json | grep -o 'repo:[^"]*'
# expect: repo:asanexample/platform:...   (not gangster)
```

## 7. Current status (as of 2026-05-29)

- ✅ SSO access granted (Admins → AdministratorAccess); `test` profile works.
- ⏸️ **`github-actions-terratest` trust still says `repo:gangster/platform`** — the org-migration code
  change is merged but the apply is **deferred** pending the §5 state-access decision.
- **Impact while deferred:** only that **Terratest CI**, if/when it runs from `asanexample/platform`,
  cannot assume `github-actions-terratest` (OIDC `sub` mismatch). **No Terratest job runs in normal PR
  CI today**, so nothing is currently failing. Complete §5 → §6 when you wire up Terratest CI.

Tracking: issue/task "Apply test-env github-oidc (account 157263244316)".
