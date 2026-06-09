# Runbook: Backstage Scaffolder GitHub App

The **write-capable** GitHub App that the Backstage scaffolder uses to open tenant-provisioning PRs against
the platform repo ([ADR-062](../adrs/062-self-service-tenant-provisioning.md) §5). It is **separate** from the
read-only catalog-discovery App ([backstage-github-app.md](backstage-github-app.md)) — that one is read-only
*forever*; never widen it.

> **Live instance:** App ID **4008946** (`asanexample-backstage-scaffolder`), created 2026-06-09. Secret:
> `platform/backstage/scaffolder-github-app` (platform account). Installed on **`asanexample/platform` only**.

## Security posture (why it's shaped this way)

A self-service PR-with-automerge flow is a privilege-delegation engine, so this credential is tightly bounded:

- **One repo only** — installed on `asanexample/platform`, nothing else.
- **PR-only** — `Contents: write` + `Pull requests: write`, nothing more. **No** Administration, Workflows,
  Actions, or Organization permissions. It *opens* PRs; it does not merge — automerge is GitHub's, gated by
  required status checks ([ADR-062](../adrs/062-self-service-tenant-provisioning.md) §3-4).
- A GitHub App scopes by **repo, not path**, so it *can* technically edit any file in the platform repo. The
  compensating controls are the **automerge path/diff restriction** + **CI-gate integrity** (only claim-path
  diffs auto-merge; the gate workflow runs from the protected base branch) — see ADR-062 §4. Treat Backstage
  as a high-value target accordingly (its other creds — ArgoCD, K8s — stay read-only).

## Create the App (org admin, ~5 min)

1. **New App:** `https://github.com/organizations/asanexample/settings/apps` → **New GitHub App**.
2. **Basics:**
   - **Name:** `asanexample-backstage-scaffolder` (globally unique)
   - **Homepage URL:** `https://backstage.aws.refplat.org`
   - **Webhook:** uncheck **Active** (the scaffolder calls GitHub; it receives no webhooks)
3. **Repository permissions** (everything else = No access):
   - **Contents:** Read and write
   - **Pull requests:** Read and write
   - **Metadata:** Read-only (mandatory, auto-selected)
   - *(Future "New App / new-repo" flow would additionally need `Administration: write` + `Workflows: write`
     to create repos with CI — the New Tenant flow does **not**, so leave them off.)*
4. **Where can this GitHub App be installed?** → **Only on this account.**
5. **Create GitHub App.**
6. On the App **General** page: note the **App ID** and **Client ID**, then
   **Private keys → Generate a private key** (downloads a `.pem` — this is the write credential, guard it).
7. **Install App** (left sidebar) → install on **asanexample** → **Only select repositories** →
   **`asanexample/platform`** → **Install**. The install URL ends in the installation ID.

## Store the private key in Secrets Manager (platform account)

Mirror the discovery-App secret shape (`{appId, privateKey}`, PEM multiline preserved). From a shell with
platform-account creds, pointing at the downloaded `.pem`:

```bash
aws secretsmanager create-secret \
  --name platform/backstage/scaffolder-github-app \
  --region us-east-1 --profile platform \
  --secret-string "$(jq -n \
      --arg appId "4008946" \
      --rawfile privateKey ./asanexample-backstage-scaffolder.<DATE>.private-key.pem \
      '{appId: $appId, privateKey: $privateKey}')"
```

Then **delete the local `.pem`** (`rm ./asanexample-backstage-scaffolder.*.private-key.pem`) — it lives in
Secrets Manager now. (`*.pem`/`*.key` are gitignored so it can't be committed, but don't leave it on disk.)

## How it's consumed

The `backstage` module (`infra/modules/backstage`) syncs this secret to a K8s Secret via an ExternalSecret
and injects `SCAFFOLDER_GITHUB_APP_ID` / `SCAFFOLDER_GITHUB_APP_PRIVATE_KEY`; `app-config.production.yaml`
registers it as a second `integrations.github.apps` entry. Backstage's `publish:github:pull-request` action
picks the App that has access to the target repo — so the write App is used only for `asanexample/platform`.
Wiring tracked in #279.

## Rotation / revocation

- **Rotate the key:** generate a new private key on the App (General → Private keys), update the Secrets
  Manager secret (`aws secretsmanager put-secret-value ...`), let the ExternalSecret resync, then delete the
  old key from the App.
- **Revoke / kill switch:** uninstall the App from `asanexample/platform` (immediately removes write access)
  or delete the App. The scaffolder's `New Tenant` flow stops being able to open PRs; nothing else is affected.
