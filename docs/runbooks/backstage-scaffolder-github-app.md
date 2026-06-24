# Runbook: Backstage Scaffolder GitHub App

The **write-capable** GitHub App that the Backstage scaffolder uses to open environment-provisioning PRs against
the platform repo ([ADR-062](../adrs/062-self-service-tenant-provisioning.md) §5). It is **separate** from the
read-only catalog-discovery App ([backstage-github-app.md](backstage-github-app.md)) — that one is read-only
*forever*; never widen it.

> **Live instance:** App ID **4008946** (`asanexample-backstage-scaffolder`), created 2026-06-09. Secret:
> `platform/backstage/scaffolder-github-app` (platform account). Installed on **`asanexample/platform` only**.

## Security posture (why it's shaped this way)

A self-service PR-with-automerge flow is a privilege-delegation engine, so this credential is tightly bounded:

- **One repo only** — installed on `asanexample/platform`, nothing else. *(The **New Product** flow widens this
  to org-wide + `Administration`/`Workflows: write` — a deliberate elevation; see
  [Elevating for New Product](#elevating-the-app-for-new-product-repo-on-demand). The base posture below is the
  claim-only flows.)*
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
   - The claim-writing flows (New Environment, Deprovision, New Team) need **only** these. The **New Product**
     flow creates a whole new app repo and needs more — see [Elevating for New Product](#elevating-the-app-for-new-product-repo-on-demand)
     below. Leave the extra permissions **off** unless you're enabling New Product.
4. **Where can this GitHub App be installed?** → **Only on this account.**
5. **Create GitHub App.**
6. On the App **General** page: note the **App ID** and **Client ID**, then
   **Private keys → Generate a private key** (downloads a `.pem` — this is the write credential, guard it).
7. **Install App** (left sidebar) → install on **asanexample** → **Only select repositories** →
   **`asanexample/platform`** → **Install**. The install URL ends in the installation ID.

## Elevating the App for New Product (repo-on-demand)

The **New Product** scaffolder template (`scaffolder/templates/new-product/`, ADR-067 §"New Product lifecycle")
**creates a new app repo** (`<team>-<product>`) via `publish:github` — and that repo ships its own CI
workflows. Creating org repos and pushing workflow files are privileges the claim-writing flows don't have, so
New Product requires elevating this App. **This is a deliberate, material privilege increase** — the App goes
from "PR-only on one repo" to "can create repos and push CI across the org" — so only do it if you're running
New Product, and keep the compensating controls (CI-gate integrity, the #197 admin-only template policy) in mind.

> ⚠️ Until these are applied, New Product renders correctly but the `publish:github` step **403s** — the rest of
> the scaffolder (New Environment, Deprovision, New Team) is unaffected and needs none of this.

**1. Add permissions** — App → **Permissions & events**
(`https://github.com/organizations/asanexample/settings/apps/asanexample-backstage-scaffolder/permissions`).
Under **Repository permissions**, add to the existing `Contents` + `Pull requests`:

- **Administration: Read and write** — authorizes `POST /orgs/asanexample/repos` (repo creation).
- **Workflows: Read and write** — the new repo contains `.github/workflows/deploy.yml`/`preview.yml`; pushing
  workflow files is gated by this (the same `workflow`-scope rule that blocks ordinary tokens).

**Save changes** — this raises a permission-update request the org owner must approve (step 2).

**2. Approve + broaden the installation** — Org → **Installed GitHub Apps** → `asanexample-backstage-scaffolder`
→ **Configure** (`https://github.com/organizations/asanexample/settings/installations`):

- **Approve** the pending Administration + Workflows request.
- **Repository access → All repositories** — so newly-created repos are covered and the App can push into them.
  (Repo creation is org-scoped; "All repositories" also gives the install the org-level reach it needs.)
  - ⚠️ This widens the App past `platform`-only. The compensating control is unchanged: only claim-path diffs
    automerge, and the CI gate runs from the protected base. The new app repos it creates start empty and get
    their delivery via the same gated GitOps path.

**3. Check the org repo-creation policy** — Org → **Settings → Member privileges → Repository creation**. If your
org restricts who may create repositories, ensure the policy doesn't block the App; an `Administration: write`
App normally creates fine, but a locked-down org policy can still gate it.

**No secret/redeploy needed:** `platform/backstage/scaffolder-github-app` (appId/privateKey) is unchanged — the
scaffolder requests fresh installation tokens with the broader scope once the request is approved. (A Backstage
pod restart isn't required but is harmless.) Verify by running **New Product** for a throwaway product and
confirming the `<team>-<product>` repo is created.

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

The `backstage` module (`infra/modules/backstage`, `enable_scaffolder = true`) syncs this secret to a K8s
Secret via an ExternalSecret and injects `SCAFFOLDER_GITHUB_APP_ID` / `SCAFFOLDER_GITHUB_APP_PRIVATE_KEY`;
`app-config.production.yaml` registers it as a second `integrations.github.apps` entry. Wiring tracked in #279.

### How Backstage picks between the two Apps (load-bearing)

Backstage resolves GitHub credentials per request from `integrations.github.apps`:

- **Repo-scoped requests** (file reads, `publish:github:pull-request`) try each App **in config order** and
  use the first whose installation covers the repo; Apps that don't cover it are skipped.
- **Org-level requests** (the catalog org discovery provider — no repo in the URL) always take the **first**
  App's token, regardless of installation repo selection.

Two consequences:

1. **Config order:** the read-only discovery App must stay **first** (org discovery breaks on the write App's
   token, which only sees `platform`); the write App is second.
2. **Disjoint installations:** the read App was also installed on `platform` (Phase 2.3, for the projection).
   Because repo-scoped lookups take the *first covering* App, that installation **shadows the write App** —
   the scaffolder would get a read-only token and PR creation 403s. One-time migration, **after** the portal
   runs an image with both Apps in config and **before** any PR-opening template ships (#280/#281): read App →
   Install App → Configure → remove `platform` (keep the app repos `<team>-<product>`, e.g. `alpha-shop`,
   `alpha-checkout`, plus `backstage`). Platform-repo
   *reads* (the projection, the template location) then resolve to the write App — fine, its Contents scope
   includes read.

### Verify after deploy

```bash
kubectl --context platform get externalsecret -n backstage backstage-scaffolder-github-app  # SecretSynced=True
```

In the portal: **Create** (`/create`) lists the platform templates (`scaffolder/templates/` in this repo); as
a platform admin, run **Hello World (scaffolder smoke test)** and see the task log. As a non-admin, templates
are visible but execution is **denied** (#197 policy: non-catalog writes are admin-only).

## Rotation / revocation

- **Rotate the key:** generate a new private key on the App (General → Private keys), update the Secrets
  Manager secret (`aws secretsmanager put-secret-value ...`), let the ExternalSecret resync, then delete the
  old key from the App.
- **Revoke / kill switch:** uninstall the App from `asanexample` (immediately removes write access) or delete
  the App. The scaffolder's PR-opening + repo-creating flows (New Environment, New Product, Deprovision, New
  Team) stop working; nothing else is affected.
- **De-elevate (drop New Product):** to walk back the elevation without killing the App, reverse
  [Elevating for New Product](#elevating-the-app-for-new-product-repo-on-demand) — remove `Administration`/
  `Workflows` from Permissions, set the install back to **Only `asanexample/platform`** — returning it to the
  PR-only base posture (New Product then 403s; the claim flows keep working).
