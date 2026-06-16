# Runbook: Product Deprovisioning (safe teardown)

> **Purpose:** remove a whole Product — its registry entry **and all of its Environments** — cleanly and
> reversibly-until-the-last-step (ADR-062). A Product owns no running resources itself; deprovisioning it is
> **two portal actions**: (1) **decommission** every Environment (a reversible suspend), then, after a grace
> window, (2) **purge** — one reviewed PR that deletes the Product + all its Environments + Releases together.
> Your only manual interaction is **approving a PR**: the Backstage *Deprovision Product* template authors both
> PRs (no `git`/`rm` by hand).
>
> **Last reviewed:** 2026-06-16

The symmetric inverse of **New Product**. For a single environment, use *Deprovision Environment* instead
(`docs/runbooks/environment-deprovisioning.md`).

## The model

| Step | What | Reversible? | How |
|------|------|-------------|-----|
| **Decommission** | `spec.lifecycle.phase: decommissioning` on **every** Environment of the Product → the Composition zeroes each ResourceQuota; workloads drain. Namespaces, IAM, ECR, the registry, the app repo — all **retained**. | **Yes** — run again with `reactivate`. | Portal **Deprovision Product** (action: `decommission`). **Reviewer-merged** (not auto-merged — draining a Product, incl. prod, warrants a human merge). |
| **Grace** | The Product sits suspended. Back up any app data now. | — | A separate time window; not CI-gated. |
| **Purge** | One PR deletes `gitops/products/<team>/<product>.yaml` + all `gitops/environments/<team>/<product>/*` + all `gitops/releases/<team>/<product>/*`. On merge: `registry-reconcile` destroys the per-Product OIDC role / ApplicationSet / Kyverno policy; ArgoCD prunes the Environments → namespaces deleted. **ECR images retained (orphan).** The app repo is **archived**. | Largely — re-onboard to recreate; ECR repos + images are reused. The repo un-archives. | Portal **Deprovision Product** (action: `purge`). **Admin-approved, never auto-merged.** |

## Procedure

1. **Decommission** (reversible)
   - Portal → Create → **Deprovision Product** → `team`, `product`, action `decommission`, type `<team>-<product>` to confirm.
   - Opens `product/decommission-<team>-<product>` setting `spec.lifecycle.phase: decommissioning` on every env claim, in one commit.
   - A reviewer merges it; ArgoCD syncs; each quota zeros; workloads drain.
   - **To reverse:** run again with action `reactivate`.

2. **Purge** (after the grace window, reviewed)
   - Portal → Create → **Deprovision Product** → action `purge`, same confirm. (Leave *Archive the app repo* checked unless you want to keep it active.)
   - Opens `product/purge-<team>-<product>` deleting the Product + all its envs + releases. The action **fails fast** if any env is still `active` — decommission first.
   - The gate runs decommission-first + completeness, and the **`gitops Approval`** check stays red until an **admin/maintainer approval (≠ you)**. If a **prod** env is in the bundle, the **release-approver** must approve too.
   - The approver merges in the GitHub UI (a human merge fires the `registry-reconcile` apply). The app repo is archived on PR open.

3. **(Optional) delete ECR images** — retained by design. Only if you truly want them gone:

   ```bash
   aws ecr delete-repository --repository-name team-<team>/<product>-<svc> \
     --force --region us-east-1 --profile platform
   ```

4. **(Optional) delete the app repo** — archived by default (reversible). To hard-delete: `gh repo delete asanexample/app-<team>-<product> --yes` (irreversible).

## What the gate enforces (`gitops Gate`)

- **Decommission-first** — an Environment claim may be deleted only if it is `decommissioning` on the base branch.
- **Completeness** — a Product may be removed only when no Environment remains (the purge bundles them, so this holds).
- **Approval** — every registry deletion needs a current-SHA admin/maintainer approval (≠ author); a **prod**-env deletion additionally needs the **release-approver**. Never auto-merged.
- **Authorship** — the scaffolder App may author the purge PR, but **only** on a `product/purge-*` branch; off that branch (or from the promote App) a bot deletion is rejected. The control is the human approval, not the authorship (ADR-062 #283).

## Data safety

- **ECR images retained** (`deletionPolicy: Orphan`) — a purge never destroys images. A later Product reusing the same `<team>/<product>` name inherits the orphaned repos; sweep them (step 3) if that's unwanted.
- **In-namespace data is NOT** — purge deletes namespaces, cascading to PVCs/PVs. Back up during the grace window.

## Verification

```bash
# After decommission (per env):
kubectl get resourcequota -n <team>-<product>-<stage> environment-quota -o jsonpath='{.spec.hard.pods}'  # "0"
# After purge:
kubectl get ns -l platform.refplat.org/environment | grep <team>-<product>   # gone
aws ecr describe-repositories --repository-names team-<team>/<product>-<svc> --profile platform  # still there
gh repo view asanexample/app-<team>-<product> --json isArchived --jq .isArchived                 # true
# The per-Product Terragrunt units converge via registry-reconcile (github-oidc / preprod-policy / argocd-apps).
```
