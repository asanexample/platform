# Runbook: GitHub Ownership App

The GitHub App the **`github-teams`** Terragrunt unit authenticates as to manage **org Teams + repo ownership**
of app repos ([ADR-072](../adrs/072-app-repo-naming-and-team-ownership.md) Flavor A). The unit derives teams from
the **Team registry** (`gitops/teams/`) and `push` grants from the **Product registry** (`gitops/products/`), so
a team is materialised in GitHub on Team-CR convergence — the same apply-on-merge moment as its Keycloak group.

> **Live instance:** _not yet created_ — fill in App ID + installation once provisioned. Secret:
> `platform/github-ownership/app` (platform account). Install **org-wide** (`asanexample`).

## Security posture (why it's shaped this way)

- **Ownership only, never a security anchor.** Org-team membership is **not** in the Actions OIDC token, so this
  App's teams can never carry the cosign / Kyverno team identity — that stays the repo name (`<team>-<product>`)
  + the per-Product IAM OIDC role. This App grants human write-access; it does **not** affect the supply chain.
- **Org-scoped + repo-admin, by necessity.** Managing org teams needs `Organization → Members: write`; granting a
  team `push` on a repo needs `Repository → Administration: write`. That is broader than the promote App (PR-only)
  — comparable to the scaffolder App. The compensating control is that it is driven **only** by the git registries
  through Terragrunt (declarative, reviewed, drift-correcting), never by ad-hoc calls.
- **IaC-driven.** Only the platform CI runner (or a break-glass operator) applies `github-teams`; there is no
  path for an app team to invoke it.

## Create the App (org admin, ~5 min)

1. **New App:** `https://github.com/organizations/asanexample/settings/apps` → **New GitHub App**.
2. **Basics:**
   - **Name:** `asanexample-github-ownership` (globally unique).
   - **Homepage URL:** `https://github.com/asanexample/platform`
   - **Webhook:** uncheck **Active** (driven by Terragrunt; receives no webhooks).
3. **Repository permissions** (everything else = **No access**):
   - **Administration:** Read and write  _(grant a team access to a repo)_
   - **Metadata:** Read-only (mandatory, auto-selected)
4. **Organization permissions:**
   - **Members:** Read and write  _(create/manage org teams)_
5. **Where can this GitHub App be installed?** → **Only on this account.**
6. **Create GitHub App.**
7. On the App **General** page: note the **App ID**, then **Private keys → Generate a private key** (downloads a
   `.pem` — guard it).
8. **Install App** (left sidebar) → install on **asanexample** → **All repositories** (org teams + future
   `<team>-<product>` repos are org-wide) → **Install**. Note the **installation ID** from the install URL
   (`.../installations/«INSTALLATION_ID»`).

## Store the credential (Secrets Manager)

The `github-teams` unit reads the App id + installation id + key from Secrets Manager during `terragrunt apply`
(as **PlatformDeployer**, the deployer role, like `keycloak-config` reads `platform/keycloak/admin`). Store it
once in the **platform** account:

```bash
AWS_PROFILE=platform aws secretsmanager create-secret \
  --name platform/github-ownership/app --region us-east-1 \
  --secret-string "$(jq -n \
      --arg id   "«APP_ID»" \
      --arg inst "«INSTALLATION_ID»" \
      --rawfile pem ./asanexample-github-ownership.private-key.pem \
      '{app_id: $id, installation_id: $inst, pem: $pem}')"
rm -f ./asanexample-github-ownership.private-key.pem   # do not keep the key on disk
```

The provider's `app_auth` block reads `app_id` / `installation_id` / `pem` from this JSON (see the unit's
`generate "github_provider"` block).

## How the unit uses it

1. `terragrunt apply` on `github-teams` reads `platform/github-ownership/app` and configures the
   `integrations/github` provider via `app_auth` (short-lived installation token, minted by the provider).
2. It reconciles `github_team` (one per `gitops/teams/<team>.yaml`) and `github_team_repository` with `push`
   (one per `gitops/products/<team>/<product>.yaml`, owning team → its `<team>-<product>` repo).
3. New Team / New Product PRs add registry files; on merge a `github-teams` apply materialises the team + grant.

## Rotation

Generate a new private key on the App, update `platform/github-ownership/app`
(`aws secretsmanager put-secret-value` with the same JSON shape), then delete the old key on the App. Re-apply
`github-teams` is **not** required (the provider reads the secret fresh on the next apply).
