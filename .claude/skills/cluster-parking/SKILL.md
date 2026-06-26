---
name: cluster-parking
description: >-
  Parking and unparking EKS environments overnight with platctl (down/up) to drop compute cost — scaling the
  managed node groups to zero (non-destructive; control plane + EBS/CNPG data preserved) and restoring them.
  Use this WHENEVER the user wants to park, unpark, scale-to-zero, "shut down for the night", or restore a
  cluster/environment for cost, or mentions `platctl down`/`up`. Parking/unparking is NOT yet stable — always
  read the Learnings log and APPEND to it after every park/unpark.
---

# Parking & unparking clusters (`platctl down` / `up`)

> **LIVING DOC — park/unpark is not yet stable.** Treat the gotchas below as *suspected* until re-confirmed, and
> **append a dated entry to the Learnings log after every park/unpark** (timing, what broke, the fix). This skill
> gets more trustworthy each cycle.

**Parking** scales an environment's EKS **managed node groups to `desiredSize=0`/`minSize=0`** via the EKS API to
drop ~all compute cost overnight. The **control plane and all EBS volumes (CNPG databases) are preserved** — it's
**non-destructive and reversible**. **Unparking** restores the node groups to their configured sizes and pods
reschedule. (To release *all* cost down to ~$0 you'd `platctl teardown` instead — a full destroy, **not** parking.)

`platctl` is built to `./bin/platctl` via `make build-platctl` (it is **not** on PATH).

## Commands — verified against the binary (it's `down`/`up`, NOT `park`/`unpark`)

```bash
make build-platctl                          # build ./bin/platctl

# Park (per-env; --env is required; --yes skips the confirmation prompt)
./bin/platctl down --env platform --yes
./bin/platctl down --env preprod  --yes

# Unpark (restore to configured node-group sizes)
./bin/platctl up --env platform
./bin/platctl up --env preprod

./bin/platctl status                        # state of the last operation
```

- **Both clusters = run it once per env** (`platform` + `preprod`). The hub (`platform`) carries ArgoCD/Crossplane/
  obs/the agent — parking it takes those down too (they reschedule on `up`); that's expected for overnight.
- The EKS API is **private** (ADR-010) — be on **Tailscale**. Node-group scaling is an AWS-API action; if a call
  needs creds use `AWS_PROFILE=management` (PlatformDeployer). `[[feedback_private_eks_use_tailscale]]`.

## Known / suspected gotchas (confirm each cycle)

- **Karpenter: `down` DOES drain it (CONFIRMED 2026-06-25).** It deletes the Karpenter **NodePool** (graceful drain →
  terminate) *before* scaling the managed `system` node group to 0 — no manual Karpenter step needed. It then
  **force-terminates** any node still draining after ~2m (e.g. a PDB-blocked lifecycle hook) — park is a full
  shutdown (EBS preserved). ⚠️ Deleting the NodePool means **`up` must recreate it** (ArgoCD / the karpenter module)
  for Karpenter to resume — watch for that on unpark.
- **⚠️ After parking, kubectl / the private k8s API is UNREACHABLE.** Scaling to zero also kills the in-cluster
  **Tailscale subnet router** that advertises the VPC CIDR, so `kubectl` times out (`i/o timeout` to the API ENI).
  This is expected, NOT a failed park. **Verify a park via the AWS EKS API, not kubectl:**
  `AWS_PROFILE=<platform|preprod> aws eks describe-nodegroup --cluster-name <env>-use1-eks --nodegroup-name system --region us-east-1 --query nodegroup.scalingConfig`
  → `desiredSize: 0`. On `up`, kubectl only works again once nodes + the TS router pod are back (give it minutes).
- **Unpark recovery** (`[[reference_preprod_scaleup_recovery]]`): after `up`, preprod has needed — (1) stale
  cross-vpc-dns PHZ → ArgoCD i/o-timeout → re-apply cross-vpc-dns + restart argocd; (2) orphaned Kyverno helm
  releases → `terragrunt import` both + apply. Also watch for a `helm` pending-upgrade lock on slow applies
  (`[[reference_helm_pending_upgrade_recovery]]`).
- **Restore sizes:** node groups come back at their configured sizes (system≈2, workload≈1 seen before).
- **Give unpark time:** scale-to-zero is fast (EKS API), but `up` + full pod reschedule + ArgoCD reconcile is
  slower — don't call it broken prematurely.
- After unparking, a quick `./bin/platctl validate --env <env>` (or `--check`) is the health gate.

## Learnings log (append a dated entry every park/unpark)

<!-- newest first -->

- **2026-06-26 — first UNPARK (platform + preprod), one `platctl up --env <env>` each. ✅ Both restored + healthy.**
  Node groups back (platform `system`=2, preprod `system`=1), kubectl reachable again once nodes + the Tailscale
  router returned (a few min after `up`), and the agent / ArgoCD / obs all Running. **`up` AUTO-HANDLES the park's
  watch-items — no manual steps:** it runs a terragrunt apply that **recreates the Karpenter NodePool**
  (`helm_release.nodepool` destroy→create) and prints **"Reconnect complete — platform can reach the restored
  preprod cluster"** (the **cross-vpc-dns reconnect** — so the historical "stale PHZ → re-apply argocd" item did NOT
  recur, nor did the Kyverno-helm-import one). `up` is slower than `down` (re-applies the karpenter module + waits
  for nodes) — ~10 min for both envs; run it in the background.
  **⚠️ False-alarm note for future unparks:** two ArgoCD apps stayed not-green but were **PRE-EXISTING, not
  unpark-caused** — `grants` (sync `Unknown`: its source path `gitops/grants` does not exist → a broken app) and
  `environments` (`OutOfSync`: the vestigial `platform-triage-copilot-dev` XEnvironment is **stuck terminating** —
  Kyverno `restrict-environment-envelope` blocks its finalizer removal — the deferred agent-moved-to-hub cleanup).
  Don't chase the standing not-green set on unpark; judge health by *new* breakage. `platctl validate` ran
  slow/inconclusive this cycle → fell back to manual checks: **AWS EKS node-group sizes + `kubectl get nodes` + key
  pods + ArgoCD app health**.

- **2026-06-25 — first skill-tracked PARK (platform + preprod), one `platctl down --env <env> --yes` each. ✅ Both
  parked.** Confirmed via the AWS EKS API: each cluster's `system` node group → `desiredSize=0, minSize=0`.
  `down` (per its own output) **drained Karpenter first** (deleted the NodePool, graceful drain → terminate), then
  scaled `system` to 0, then **force-terminated** PDB-blocked nodes after ~2m (2 on platform, 1 on preprod). ~2–3 min
  per env. There is only **one managed node group per cluster (`system`)** — workload capacity is Karpenter, whose
  NodePool is deleted on park. **Gotcha hit:** `kubectl` was unreachable right after (Tailscale subnet router gone) —
  `i/o timeout` to the API ENI — so I verified via the AWS EKS API instead (now a documented step above). Ran the
  `down` itself with `AWS_PROFILE=management`; the AWS-API verify used the per-account `platform`/`preprod` profiles.
  **Unpark NOT yet exercised this cycle** — open watch-items for next `up`: NodePool recreation, Tailscale router
  return (kubectl reachability), and the `[[reference_preprod_scaleup_recovery]]` items (cross-vpc-dns PHZ, orphaned
  Kyverno helm releases).
