# Runbook: Backstage GitHub App (catalog discovery)

> **Purpose:** a read-only GitHub App that lets Backstage discover `catalog-info.yaml` across the
> `asanexample` org (BACK-stack Phase 2.2). Bounds Backstage's GitHub read surface (it's an internet-adjacent
> read window) far better than a PAT.
>
> **Last reviewed:** 2026-06-03

---

## Overview

Backstage's `GithubEntityProvider` (config in the image's `app-config.production.yaml` →
`catalog.providers.github` + `integrations.github.apps`) authenticates as a **read-only GitHub App** to scan the
org for `catalog-info.yaml`. The App's `appId` + private key live in Secrets Manager and reach the pod via an
ExternalSecret → env (`GITHUB_APP_ID` / `GITHUB_APP_PRIVATE_KEY`), wired by `infra/modules/backstage`.

**This App is read-only, forever.** The Phase-3 Scaffolder's *write* access (PR/repo creation) is a **separate**
App/decision — never widen this one.

---

## Initial Setup (manual — GitHub can't be Terraformed here)

### Step 1: Create the GitHub App

1. `asanexample` org → **Settings → Developer settings → GitHub Apps → New GitHub App**.
2. Name: `asanexample-backstage` (or similar). Homepage URL: `https://backstage.aws.refplat.org`.
3. **Uncheck "Active" under Webhook** (no webhook needed — backend app-only auth).
4. **Permissions → Repository permissions:**
   - **Contents: Read-only**
   - **Metadata: Read-only** (auto-selected)
   - everything else: No access.
5. **Where can this GitHub App be installed?** → *Only on this account*.
6. Create. Note the **App ID**.
7. **Generate a private key** (bottom of the App's page) → downloads a `.pem`. Keep it safe; you'll store it in
   Secrets Manager and can delete the local copy after.

### Step 2: Install on SELECTED repos only

App page → **Install App** → install into the `asanexample` org → **Only select repositories** →
**`app-alpha`, `app-bravo`, `backstage`**. (NOT all repos, NOT `platform` — discovery surface = install scope.
`platform` is added in Phase 2.3 when the projection reads it.)

### Step 3: Store the credential in Secrets Manager

```bash
PEM=$(cat ~/Downloads/asanexample-backstage.*.private-key.pem)
aws secretsmanager create-secret \
  --name platform/backstage/github-app \
  --secret-string "$(jq -n --arg appId "<APP_ID>" --arg pk "$PEM" '{appId:$appId, privateKey:$pk}')" \
  --region us-east-1 --profile platform
# jq escapes the PEM newlines into the JSON; the ExternalSecret extracts the privateKey property back to a
# multiline string. Then `rm` the local .pem.
```

### Step 4: Deploy

The App secret is read by the central External Secrets SA (`platform/*`); the backstage module's
`github_app_external_secret` projects it into the namespace as `backstage-github-app` and injects the env.

```bash
# After the asanexample/backstage image with the discovery config is merged + built, bump image_tag and apply:
AWS_PROFILE=management terragrunt apply --working-dir infra/live/aws/platform/us-east-1/platform/backstage
```

---

## Verification

```bash
kubectl --context platform get externalsecret -n backstage backstage-github-app   # SecretSynced=True
kubectl --context platform logs -n backstage -l app.kubernetes.io/name=backstage | grep -i github
# expect GithubEntityProvider discovery, no auth errors
```

Then in the catalog UI (`backstage.aws.refplat.org`) → **Components** → `app-alpha`, `app-bravo`, `backstage`
appear, each owned by its team Group, within the provider's schedule (~10 min) or after a manual refresh.

---

## Troubleshooting

- **No Components appear:** check the App is installed on those repos, the repos have `catalog-info.yaml` on
  `main`, and the discovery `filters.repository` regex matches. Force a refresh from the entity/catalog page.
- **`401`/`integration not found`:** `GITHUB_APP_ID`/`GITHUB_APP_PRIVATE_KEY` not in the pod, or the PEM lost its
  newlines. Confirm the ExternalSecret synced and the env carries a valid multiline PEM; if the env form breaks,
  mount the key as a file and use `$file` in `integrations.github.apps[].privateKey`.
- **Discovered an entity it shouldn't:** `catalog.rules` limits discovery to `[Component, Location]`; an app repo
  trying to register a `Group`/`System` is rejected (by design — app `catalog-info` is untrusted self-assertion).
