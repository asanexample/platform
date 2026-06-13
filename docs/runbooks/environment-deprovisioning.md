# Runbook: Environment Deprovisioning (safe teardown)

> **Purpose:** wind an environment down safely (ADR-062, #283). Removing an environment claim hard-deletes the namespace,
> so deprovisioning is **two steps with a reversible grace window**: (1) **decommission** — a reversible
> "suspend" that stops workloads but keeps everything; then, after a grace window, (2) **purge** — a reviewed
> PR that removes the claim. ECR images survive a purge (retained), so there is no *accidental* one-shot
> destroy path.
>
> **Last reviewed:** 2026-06-12

---

## The model

| Step | What | Reversible? | How |
|------|------|-------------|-----|
| **Decommission** | `spec.lifecycle.phase: decommissioning` → the Composition zeroes the ResourceQuota (pods + cpu/memory → 0). No new/rescheduled pod can run; workloads drain on the next reconcile. Namespace, IAM, ECR, policies all **retained**. | **Yes** — flip phase back to `active` and the quota is restored. | Backstage **Deprovision Environment** template (action: decommission), or edit the claim. Automerges (reversible). |
| **Grace** | The environment sits suspended. Back up any app data now (see below). | — | A separate PR / time; not CI-time-gated. |
| **Purge** | Remove the claim file → ArgoCD prune deletes the XEnvironment → Crossplane deletes the namespace. **ECR is orphaned (images kept).** | Largely — re-add the claim to recreate the namespace/IAM; ECR repo + images are reused. | A **human-authored, reviewed** PR (the gate requires it). |

## What the gate enforces (`gitops Gate`)

- A claim may be **deleted only if it is `decommissioning` on the base branch** — you cannot one-shot delete an
  active environment (the decommission must merge first, in its own PR → a real reversible window).
- A deletion PR requires a **current-SHA admin/maintainer approving review** (main has no required-review rule,
  so this machine-enforces "deletes are reviewed"; GitHub blocks self-approval → a platform reviewer must sign
  off the destroy).
- The scaffolder write App **never** authors a delete — the purge is always a human PR.
- A decommissioning environment is **excluded from the team's aggregate quota** (it's winding down).

## Data safety — read this

- **ECR images are retained.** The repo is `team-<team>/<product>-<svc>` (Product/Service-scoped, shared across
  the product's environments/stages); it carries `deletionPolicy: Orphan`, so a purge never destroys images
  another environment might use. The **only** way to delete images is a deliberate manual purge
  (`aws ecr delete-repository`) or the cluster-teardown ECR orphan sweep.
- **In-namespace data is NOT.** A purge deletes the namespace, which cascades to anything inside it —
  including **PVCs/PVs (and their EBS volumes)** an app created. The platform cannot retain resources it does
  not own. The grace window is your chance to **back up app data before purging**; a *deliberate* purge can
  still drop un-backed-up app state. (Today no environment provisions PVCs, so the live risk is nil — but don't
  assume a purge preserves app data.) Backup-on-decommission via `status.lifecycle.exitAttestation` is a
  future hook, not implemented.

## Procedure

### 1. Decommission (reversible)

Portal → **Create** → **Deprovision Environment** → pick the team + product + stage, action **decommission**,
type the environment name to confirm. It opens a PR setting `spec.lifecycle.phase: decommissioning` +
`platform.refplat.org/decommissioned-at`. The PR automerges (reversible); ArgoCD syncs → the environment's quota
zeroes → the app drains.

(Or by hand: edit `gitops/environments/<team>/<product>/<stage>[-<customer>].yaml`, add `spec.lifecycle.phase:
decommissioning`, open a PR.)

**To reverse:** run the template with action **reactivate** (or set the phase back to `active`); the quota is
restored and workloads schedule again.

### 2. Purge (after the grace window, reviewed)

Open a PR that **removes** the claim file. Verify any app data is backed up first. The gate validates that the
environment is `decommissioning` and requires an admin review. On merge, ArgoCD prunes the XEnvironment; the
namespace is deleted; **the ECR repo + images remain** in AWS.

```bash
git rm gitops/environments/<team>/<product>/<stage>[-<customer>].yaml
# PR → admin review → merge
```

### 3. (Optional) delete the ECR images

Only if you truly want the images gone and no other environment/stage of that product needs them:

```bash
aws ecr delete-repository --repository-name team-<team>/<product>-<svc> --force --region us-east-1 --profile platform
```

## Verification

```bash
NS=<team>-<product>-<stage>
# After decommission:
kubectl --context preprod get resourcequota -n $NS environment-quota -o jsonpath='{.spec.hard.pods}'  # "0"
kubectl --context preprod get ns $NS   # still Active (retained)
# After purge:
kubectl --context preprod get ns $NS   # NotFound
aws ecr describe-repositories --repository-names team-<team>/<product>-<svc> --region us-east-1 --profile platform  # still there
```

## Residual / out of scope

- **Direct `kubectl delete xenvironment` by a platform principal** bypasses the gate (it's the git-path control).
  No admission delete-guard is installed because it would break `platctl teardown` + ArgoCD prune. Platform
  principals are trusted/break-glass.
- **Hard retention duration** (e.g. "must wait 24h") is not CI-enforced (clock flakiness + would block
  legitimate teardown). `status.lifecycle.retentionUntil` + a reaper is the future path.
