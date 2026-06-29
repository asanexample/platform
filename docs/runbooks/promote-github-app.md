# Runbook: Promote GitHub App

The **write-capable** GitHub App that app CI uses to open **release digest-bump PRs** against the platform repo
([ADR-071](../adrs/071-digest-promotion-via-control-plane.md)). It is the mechanism that lets an app's `main` stay
**fully protected and CI-untouched**: instead of pushing a digest pin to its own `main`, the app's `deploy.yml`
calls the shared `trusted-ci/promote.yml` workflow, which (as this App) opens a gated PR bumping
`gitops/releases/<team>/<product>/<stage>.yaml`. The gitops Gate validates + auto-merges it.

> **Live instance:** App ID **4060090** (`asanexample-promote`), created 2026-06-15. Secret:
> `platform/promote/github-app` (platform account, stored). Installed on **`asanexample/platform`**
> (installation `140462682`). Fully provisioned — ready for `promote.yml`.

## Security posture (why it's shaped this way)

This is a delegation engine — every app's CI can mint a token from it — so it is the **most tightly bounded**
write App on the platform:

- **One repo only** — installed on `asanexample/platform`, nothing else. It never touches an app repo.
- **PR-only** — `Contents: write` + `Pull requests: write`, nothing more. **No** Administration, Workflows,
  Actions, or Organization permissions. It _opens_ PRs; it does **not** merge — auto-merge is GitHub's, gated by
  the required gitops-Gate checks (ADR-062 §3-4, the same path the scaffolder uses).
- **Strictly narrower than the scaffolder App** — no repo-create, no org scope. Where the scaffolder App is
  elevated for New Product (repo-on-demand), this App is **never** elevated.
- A GitHub App scopes by **repo, not path**, so it _can_ technically edit any file in the platform repo. The
  compensating controls are the gate's **auto-merge path/diff restriction** (only `gitops/releases/**`,
  non-deletion, validated, promote-App-authored PRs auto-merge — see `validate-releases.sh` + `classify-diff.sh`)
  and **CI-gate integrity** (the gate runs from the protected base branch). A malformed or off-path PR is
  validated and left for human review, never auto-merged.

## Create the App (org admin, ~5 min)

1. **New App:** `https://github.com/organizations/asanexample/settings/apps` → **New GitHub App**.
2. **Basics:**
   - **Name:** `asanexample-promote` (globally unique; the bot login becomes `asanexample-promote[bot]` — it must
     match `PROMOTE_APP_LOGIN` in `.github/workflows/gitops-gate.yml`, else release PRs validate but never
     auto-merge).
   - **Homepage URL:** `https://github.com/asanexample/platform`
   - **Webhook:** uncheck **Active** (the App is called by CI; it receives no webhooks).
3. **Repository permissions** (everything else = **No access**):
   - **Contents:** Read and write
   - **Pull requests:** Read and write
   - **Metadata:** Read-only (mandatory, auto-selected)
4. **Where can this GitHub App be installed?** → **Only on this account.**
5. **Create GitHub App.**
6. On the App **General** page: note the **App ID**, then **Private keys → Generate a private key** (downloads a
   `.pem` — guard it).
7. **Install App** (left sidebar) → install on **asanexample** → **Only select repositories** →
   **`asanexample/platform`** → **Install**.

## Store the credential (Secrets Manager)

The shared `promote.yml` reads the App's id + key from Secrets Manager via the app's **existing per-Product OIDC
role** (the same role `build-sign.yml` assumes for ECR push) — no GitHub org secret, no key in any app repo. Store
it once in the **platform** account:

```bash
AWS_PROFILE=platform aws secretsmanager create-secret \
  --name platform/promote/github-app --region us-east-1 \
  --secret-string "$(jq -n --arg id "«APP_ID»" --rawfile key ./asanexample-promote.private-key.pem \
      '{app_id: $id, private_key: $key}')"
rm -f ./asanexample-promote.private-key.pem   # do not keep the key on disk
```

The per-Product OIDC roles are granted `secretsmanager:GetSecretValue` on this secret automatically (the
`github-oidc` unit derives the grant for every Product — ADR-071 PR3). After adding a new Product, re-apply
`github-oidc` (or let the registry-reconcile job do it — ADR-071 Workstream 2) so its role can read the secret.

## How the promote flow uses it

1. App `deploy.yml` builds + cosign-signs + pushes the image (shared `build-sign.yml`), then calls
   `trusted-ci/promote.yml` with `{team, product, stage, customer?, service, digest}`.
2. `promote.yml` assumes the app's per-Product OIDC role (OIDC), reads `platform/promote/github-app`, and mints a
   short-lived installation token (`actions/create-github-app-token`).
3. With that token it checks out the platform repo, bumps `gitops/releases/<team>/<product>/<stage>[-<customer>].yaml`,
   pushes a branch, and opens a PR — authored as `asanexample-promote[bot]`.
4. The gitops Gate validates (`validate-releases.sh`) and auto-merges (App-authored, release-only, non-deletion).
   The per-Product ApplicationSet then injects the digest; the app repo's `main` is never touched.

> **Second consumer — the platform-side reconciler.** `platform/promote/github-app` is **also** read by the
> in-repo `.github/workflows/auto-promote.yml` reconciler. It runs on the `platform-infra` ARC runners, assumes
> **PlatformDeployer** (not a per-Product OIDC role) to read the secret, and mints the same promote-App token to
> open Release PRs when reconciling the promotion ladder. Factor this consumer in when storing/rotating the secret —
> PlatformDeployer must retain `secretsmanager:GetSecretValue` on it.

## Rotation

Generate a new private key on the App, update `platform/promote/github-app`
(`aws secretsmanager put-secret-value`), then delete the old key on the App. No app-repo change needed.
