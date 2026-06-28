# Runbook: ARC GitHub App credential

The self-hosted runner controller (ARC, ADR-065 / #323) authenticates to GitHub as a **GitHub App** to
register runners and pick up jobs. The App is created once by hand; its credentials live in AWS Secrets
Manager and are projected into the cluster by an ExternalSecret (the `actions-runner-controller` module).

This is the one manual prerequisite before applying the `actions-runner-controller` unit (mirrors the
Backstage GitHub-App pattern, `backstage-github-app.md`).

## 1. Create the GitHub App (org `asanexample`)

Open the org's **New GitHub App** form directly:

<https://github.com/organizations/asanexample/settings/apps/new>

(Equivalent path: the org's Settings → Developer settings → GitHub Apps → **New GitHub App**. Create it as an
**org-owned** App — not a personal one — so ownership survives any one person leaving.) Fill in:

- **Name:** `asanexample-arc-runners` (or similar)
- **Homepage URL:** any (e.g. the repo URL)
- **Webhook:** uncheck **Active** (ARC polls; no webhook needed)
- **Repository permissions:**
  - **Administration:** Read and write — *required* to register self-hosted runners
  - **Metadata:** Read-only (implicit)
  - (Actions read is not required for repo-level runner sets)
- **Where can this app be installed:** Only on this account

Create it, then note the **App ID**.

## 2. Generate a private key + install

- On the App page → **Private keys** → **Generate a private key** (downloads a `.pem`).
- **Install App** → install on the **`platform`** repo only (repo-scoped pool). After installing, the URL is
  `.../installations/<INSTALLATION_ID>` — note the **Installation ID**.
- Shortcut for the IDs (no UI hunting): once installed,
  `gh api /orgs/asanexample/installations --jq '.installations[] | select(.app_slug=="asanexample-arc-runners") | {app_id, installation_id: .id}'`
  prints both the **App ID** and **Installation ID**. (This endpoint requires an
  org-admin token — your `gh` auth must hold org-owner/admin scope on `asanexample`.)

## 3. Store in Secrets Manager

The secret name must match `github_app_secret_name` in the unit
(`platform/gha-runner-controller/github-app`), with JSON keys `appId`, `installationId`, `privateKey`:

```bash
# Run from a profile that assumes PlatformDeployer (e.g. AWS_PROFILE=management), us-east-1, platform account.
aws secretsmanager create-secret \
  --name platform/gha-runner-controller/github-app \
  --region us-east-1 \
  --secret-string "$(jq -n \
      --arg appId "<APP_ID>" \
      --arg installationId "<INSTALLATION_ID>" \
      --rawfile privateKey ./arc-app.private-key.pem \
      '{appId:$appId, installationId:$installationId, privateKey:$privateKey}')"

# Then shred the local key:
rm -f ./arc-app.private-key.pem
```

(To rotate later: `aws secretsmanager put-secret-value --secret-id platform/gha-runner-controller/github-app …`;
the ExternalSecret resyncs within its refresh interval.)

## 4. Apply

Apply the `actions-runner-controller` unit (locally / via platctl — it's the break-glass floor, ADR-065).
The ExternalSecret projects the creds into the `arc-github-app` secret in the `arc-runners` namespace, the
controller authenticates, and the `platform-infra` runner scale set registers (visible under the repo's
**Settings → Actions → Runners → Runner scale sets**, idle at 0).
