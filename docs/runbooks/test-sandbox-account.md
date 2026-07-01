# Runbook — The Test Account (`157263244316`)

How the **Test** AWS account is set up, how to get access, and how its IaC is applied. The Test account
runs **Terratest** (Go integration tests in `infra/tests/aws/`) on a schedule + on demand, creating and
destroying real AWS resources blast-radius-isolated from platform/preprod/prod. Companion to the
[IAM roles](../../AGENTS.md#iam-roles) and [GitHub OIDC](../adrs/036-github-actions-oidc-federation.md)
docs.

---

## 1. What it is

| | |
|---|---|
| **Account ID** | `157263244316` |
| **Name / email** | `Test` / `josh+test@deeden.org` |
| **Purpose** | Isolated sandbox where Terratest deploys/destroys real AWS resources (`test-aws.yml`, scheduled + `workflow_dispatch`). |
| **Persistent resources** | GitHub OIDC provider + `github-actions-terratest` (AdministratorAccess, OIDC-assumable from `asanexample/platform` CI on `main`/`feat/*`) + `PlatformDeployer`. Defined by `infra/live/aws/test/global/{github-oidc,iam-roles}/`. |

## 2. It's a standard, `PlatformDeployer`-managed account

The Test account is onboarded to the **same posture as platform/preprod**: `PlatformDeployer` is the IaC
principal, and applies run `AWS_PROFILE=management` → assume `PlatformDeployer` (§4).

We considered keeping it "minimal" (apply directly as a human SSO admin, no `PlatformDeployer`), but an
**org SCP makes that impossible** and shows the intended design:

> **SCP `p-z590g1lk`, statement `DenyTeamTagTampering`** denies mutating the **`Team`** tag key only —
> scoped via `aws:TagKeys = ["Team"]` across `iam:TagRole`/`UntagRole`, `ecr:TagResource`/`UntagResource`,
> `secretsmanager:TagResource`/`UntagResource`, and `ec2:CreateTags`/`DeleteTags` — for **every** principal
> **except** the full `exempt_role_arns` set (the seven `exempt_roles`, incl. `PlatformDeployer` and
> `github-actions-terratest`) **plus** AWS **service-linked roles** (`role/aws-service-role/*`). It protects
> the `Team`/ABAC tags (#61/#62).

So a human SSO admin cannot reconcile IAM tags — only `PlatformDeployer` (or break-glass) can. The org
guardrails are explicitly built around `PlatformDeployer` managing every account, so the Test account
gets one too. Since it deploys real infrastructure regularly, that's also the right call on merits.

## 3. Granting human (SSO) access

The Test account is in the org but assigns no SSO permission set by default. To grant access:

1. **IAM Identity Center** (management account, `us-east-1`) → **AWS accounts** → **Test
   (`157263244316`)** → **Assign users or groups**.
2. **Groups** tab → **Admins** ("Full administrator access to all accounts") → **Next**.
3. Permission set → **AdministratorAccess** → **Submit**.

Local profile (add to `~/.aws/config` if missing):

```ini
[profile test]
sso_session = management
sso_account_id = 157263244316
sso_role_name = AdministratorAccess
region = us-east-1
```

`aws sso login --profile test` (if the cached session predates the assignment), then
`aws sts get-caller-identity --profile test` → `157263244316`.

> Human SSO admin in the Test account can do most things, but **not** mutate the **`Team`** tag on
> IAM/ECR/Secrets/EC2 resources (SCP §2). Run IaC via `PlatformDeployer`, not as the SSO admin.

## 4. Applying test-env IaC (the normal path)

Same as every other account — run from management; `infra/root.hcl` assumes `PlatformDeployer` in the
target account, and the state backend uses `TerraformStateAccess` (which already trusts management):

```bash
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
cd infra/live/aws/test/global/<unit>          # e.g. github-oidc, iam-roles
AWS_PROFILE=management terragrunt plan -out=tfplan.bin
AWS_PROFILE=management terragrunt apply tfplan.bin
```

`PlatformDeployer` is SCP-exempt, so tag reconciliation works. No overrides, no break-glass.

## 5. One-time bootstrap (how `PlatformDeployer` was created) — reference

Chicken-and-egg: the first apply of `iam-roles` can't assume `PlatformDeployer` because it doesn't exist
yet, and a human SSO admin can't create+tag it (SCP §2). Resolved by applying that **first** unit through
the SCP-exempt **`OrganizationAccountAccessRole`** via a temporary provider override, while the backend
still runs from management. Procedure (repeat for any new account that lacks `PlatformDeployer`):

1. Author the `iam-roles` unit (`infra/live/aws/test/global/iam-roles/terragrunt.hcl`) — `PlatformDeployer`
   trusting management + the account's SSO AdministratorAccess, with `AdministratorAccess`.
2. Drop a **temporary** `bootstrap_override.tf` next to it:

   ```hcl
   provider "aws" {
     assume_role { role_arn = "arn:aws:iam::157263244316:role/OrganizationAccountAccessRole" }
   }
   ```

3. `AWS_PROFILE=management terragrunt plan -out=tfplan.bin && … apply tfplan.bin` — backend assumes
   `TerraformStateAccess` (trusts management); the override makes the provider assume the SCP-exempt
   `OrganizationAccountAccessRole`, which can create+tag `PlatformDeployer`.
4. **Delete `bootstrap_override.tf`.** All subsequent applies use the normal §4 path.

> Break-glass (`OrganizationAccountAccessRole`) is used **only** for this one-time bootstrap and is
> otherwise reserved for emergencies. The apply requires explicit operator authorization.

## 6. Status (2026-05-30)

- ✅ SSO access (Admins → AdministratorAccess); `test` profile works.
- ✅ `PlatformDeployer` bootstrapped in the Test account.
- ✅ `github-actions-terratest` trust updated to `repo:asanexample/platform` (`main` + `feat/*`).
- ✅ Verified end-to-end: a `test-aws.yml` dispatch authenticated to AWS via OIDC under
  `asanexample/platform` (the "Configure AWS credentials" step succeeded), confirming Terratest CI works
  under the new org.

Terratest CI (`test-aws.yml`) runs on a schedule + `workflow_dispatch`.
