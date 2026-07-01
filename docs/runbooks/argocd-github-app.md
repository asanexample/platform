# Runbook: ArgoCD GitHub App

The **read-only** GitHub App ArgoCD authenticates to GitHub as, for two purposes: cloning private app
repos to sync Applications (repo-creds, TD2-02b) and, since ADR-032, the `pullRequest` generator that
powers PR-preview delivery (`infra/modules/argocd-apps/pr-preview.tf`). Replaced a PAT
(`platform/github/argocd-pat`, now retired) — no user-tied credential, no expiry churn, higher API
rate limits, install-scoped to specific repos.

> **Live instance:** App **`asanexample-argocd`** (App ID `143362855`), installed org-wide on
> `asanexample`. Secret: `platform/argocd/github-app` (platform account): `{appId, installationId,
> privateKey}`. Permissions: **Contents: Read-only**, **Metadata: Read-only**, **Pull requests:
> Read-only**.

## Security posture (why it's shaped this way)

- **Read-only, full stop.** No `Contents: write`, no `Pull requests: write` — ArgoCD only ever clones
  and reads. It cannot push, comment, or open anything. Contrast with the [Promote GitHub
  App](promote-github-app.md) (write-capable, but repo-scoped to `asanexample/platform` only) or the
  [scaffolder App](backstage-scaffolder-github-app.md) (write-capable, repo-creation).
- **Org-wide install is intentional here** — ArgoCD needs to clone and list PRs for *every* app repo
  it might ever deliver to, and adding a repo shouldn't require re-installing the App. The blast
  radius of a leaked read-only token is still bounded to read access on installed repos, not write.
- **Two consumers, one credential.** Both `argocd`'s repo-creds `ExternalSecret`
  (`github-asanexample-app-creds`, in the `argocd` namespace) and `argocd-apps`'s PR-preview
  `pullRequest` generator (`var.github_app_secret_name` → `appSecretName`) read the same
  `platform/argocd/github-app` secret. The repo-creds `ExternalSecret`'s target keys
  (`githubAppID`/`githubAppInstallationID`/`githubAppPrivateKey`) are exactly what ArgoCD's
  `appSecretName` generator auth expects too — no second secret to provision.

## Create the App (org admin, ~5 min)

1. **New App:** `https://github.com/organizations/asanexample/settings/apps` → **New GitHub App**.
2. **Basics:**
   - **Name:** `asanexample-argocd` (globally unique).
   - **Homepage URL:** `https://argocd.aws.refplat.org` (or the platform repo).
   - **Webhook:** uncheck **Active** — ArgoCD polls (repo-creds on sync, the PR generator on
     `requeueAfterSeconds`); it doesn't need inbound webhooks from GitHub. (EKS is private, ADR-010 —
     GitHub couldn't reach a webhook endpoint here anyway.)
3. **Repository permissions** (everything else = **No access**):
   - **Contents:** Read-only
   - **Pull requests:** Read-only
   - **Metadata:** Read-only (mandatory, auto-selected)
4. **Where can this GitHub App be installed?** → **Only on this account.**
5. **Create GitHub App.**
6. On the App **General** page: note the **App ID**, then **Private keys → Generate a private key**
   (downloads a `.pem` — guard it).
7. **Install App** (left sidebar) → install on **asanexample** → **All repositories** (or the
   specific set ArgoCD delivers to, if you'd rather scope it tighter — org-wide is the live choice)
   → **Install**.

## Store the credential (Secrets Manager)

```bash
AWS_PROFILE=platform aws secretsmanager create-secret \
  --name platform/argocd/github-app --region us-east-1 \
  --secret-string "$(jq -n --arg appId "«APP_ID»" --arg installationId "«INSTALLATION_ID»" \
      --rawfile privateKey ./asanexample-argocd.private-key.pem \
      '{appId: $appId, installationId: $installationId, privateKey: $privateKey}')"
rm -f ./asanexample-argocd.private-key.pem   # do not keep the key on disk
```

The `argocd` unit's `github_repo_creds` generate block (`infra/live/aws/platform/us-east-1/platform/argocd/terragrunt.hcl`)
projects this via an `ExternalSecret` into `github-asanexample-app-creds` (namespace `argocd`), which
both ArgoCD's repo-creds *and* the `argocd-apps` unit's `github_app_secret_name` input reference.

## Adding permissions later (PR-preview cutover, 2026-07-01)

Editing an App's requested permissions in its settings does **not** automatically apply to an
existing installation — GitHub requires a separate approval step. After adding **Pull requests:
Read-only** to this App (to enable ADR-032's `pullRequest` generator), the install still showed only
the old permission set (verified via `gh api /orgs/asanexample/installations`) until an org owner
visited the App's installation page and accepted the "requesting new permissions" prompt. If you add
a permission to this App in the future, expect the same two-step: edit the App, then separately
accept the permission update on the installation before it takes effect.

## Rotation

Generate a new private key on the App, update `platform/argocd/github-app`
(`aws secretsmanager put-secret-value`), then delete the old key on the App. ESO's `refreshInterval:
1h` on the repo-creds `ExternalSecret` picks it up within the hour; the PR-preview ApplicationSet
reads the same secret via `appSecretName` on its next reconcile.

## Related

- [Migrate ArgoCD GitHub auth from PAT to GitHub App](https://github.com/asanexample/platform/issues/111) — the issue this App closes (repo-creds *and* the PR-preview generator token, both now on this App).
- [PR Preview Environments (ADR-032)](../adrs/032-pr-preview-environments.md)
- [`argocd-app-delivery` skill](../../.claude/skills/argocd-app-delivery/SKILL.md)
