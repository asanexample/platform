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
  (`[[reference_helm_pending_upgrade_recovery]]`). **(2026-06-26+: `up` now AUTO-handles the cross-vpc-dns
  reconnect + Karpenter NodePool recreation — these largely no longer need manual steps; see the log.)**
- **⚠️ Unpark forces a FRESH ADMISSION of every pod → it EXPOSES latent admission-webhook / IAM bugs that were
  masked while pods ran continuously.** 2026-06-27: post-unpark NO product workload could be re-created — the
  Deployment sat at `0/1` with no pod, and the ReplicaSet showed `FailedCreate: admission webhook
  "mutate.kyverno.svc-fail" denied` → cosign **verify-images** couldn't pull the image signature from ECR
  (`kyverno-ecr` role `ecr:BatchGetImage` DENIED). It was a **latent bug, not unpark damage**: the platform
  `policy` unit never set `ecr_account_id`, so the `kyverno-ecr` ECR ARN rendered account-less
  (`arn:aws:ecr:us-east-1::repository/team-*`) → matched no repo → zero ECR access. Invisible until a *fresh*
  admission (the agent pod had run continuously). **Diagnostic path:** `get pods` (none) → `get rs` (FailedCreate)
  → `describe rs` (the full admission error) → the `kyverno-ecr` role's inline policy. Fix: set `ecr_account_id`
  on the unit, **targeted**-apply `aws_iam_role_policy.kyverno_ecr` (skips bundled pre-existing chart drift), then
  delete the stuck RS to clear its FailedCreate backoff. ⚠️ Restarting Kyverno does NOT fix an IAM gap (IAM is
  evaluated at call-time, not cached in creds) — don't waste the detour. **(platform #875: `platctl up`'s
  `recoverKyverno` now re-checks after its Kyverno restart and SURFACES the actual `FailedCreate` admission error
  when a block persists — so a non-transient cause like this announces itself instead of leaving silent stuck pods.)**
- **Post-unpark DNS/secret gap → RESTART startup-only-connect workloads.** CoreDNS + ESO aren't ready instantly:
  pods that start during the gap log transient `connection refused` to kube-dns (`172.20.0.10:53`), and ESO may
  briefly fail its SecretsManager sync. A workload that connects to a dependency ONLY at startup (e.g. the triage
  agent's `directory.Open`) degrades to its fallback and stays there — restart it once DNS/ESO are healthy. ⚠️ A
  `kubectl rollout restart` is reverted by ArgoCD selfHeal (the annotation reads as drift) — **delete the pod (or
  RS)** to force a clean restart instead.
- **Bastions: `down`/`up` now stop/start the SSM bastion automatically (platform #875)** — a park is truly
  cost-zero with no manual `ec2 stop-instances` step (discovered by the derived `<cluster>-ssm-bastion` Name tag;
  no-op if absent). The classifier still **gates `platctl down`/`up` until an EXPLICIT, emphatic user go** — a
  vague "park it" got blocked; "scale down no matter what" cleared it.
- **Unpark: the NodePool can return while its EC2NodeClass does NOT — zero workload capacity (now fixed).** Symptom:
  `kubectl get ec2nodeclass` empty + `nodepool` READY=False (`NodeClassReady=False`) + every workload pod Pending +
  karpenter logs `ignoring nodepool, not ready`. Cause was the down/up asymmetry — `down` deleted only the NodePool,
  so `up`'s force-replace lost the leftover finalizer'd EC2NodeClass to a Terminating race. Fixed: `down` now deletes
  BOTH CRs symmetrically and `up` asserts EC2NodeClass-present + NodePool Ready=True before declaring restored. If it
  ever recurs, unblock with `helm get manifest karpenter-nodepool -n karpenter | kubectl apply -f -` (recreates the
  NodeClass with no destructive uninstall) — NOT another `-replace`.
- **Restore sizes:** node groups come back at their configured sizes (system≈2, workload≈1 seen before).
- **Give unpark time:** scale-to-zero is fast (EKS API), but `up` + full pod reschedule + ArgoCD reconcile is
  slower — don't call it broken prematurely.
- After unparking, a quick `./bin/platctl validate --env <env>` (or `--check`) is the health gate.

## Learnings log (append a dated entry every park/unpark)

<!-- newest first -->

- **2026-07-02 (afternoon) — full PARK + UNPARK on both clusters to VALIDATE the refactored `platctl`
  binary (the code-quality-pass PR #1103, built from the merged `main`). ✅ Both cycled cleanly — the refactor
  introduced ZERO regressions — and the cycle surfaced one NEW class of post-unpark stuck workload, now fixed
  in `up`.** PARK: `platctl down --env <env> --yes` each. Platform pristine ("Karpenter nodes drained and
  terminated" + "EC2NodeClass deleted"). Preprod threw the familiar slow-drain warnings ("NodeClaims still
  present after 6m", "EC2NodeClass still present after 90s") but was **cost-safe** — verified via the AWS API:
  the one lingering Karpenter instance was `shutting-down`, and zero running/pending cluster instances. UNPARK:
  `platctl up --env <env>` each (from the MAIN checkout — `up` runs terragrunt applies). **Both Karpenter gates
  passed on the FIRST check** ("Karpenter ready: EC2NodeClass present, NodePool(s) Ready=True") — no self-heal
  needed, no repeat of the morning's stuck-NodeClass incident (clean because `down` deleted the NodeClass
  symmetrically, so `up` recreated both from scratch). Preprod reconnect (cross-vpc-dns + argocd restart) clean.
  **THE NEW FINDING (the reason to actually check pod readiness, not just node/nodegroup state): `backstage` sat
  `0/1 Running` for 33 min post-unpark** — liveness OK, readiness a steady `503`. Root cause: backstage started
  ~17 min BEFORE its CNPG database (`backstage-db`) was Ready, failed every DB-backed plugin with `connect
  ECONNREFUSED …:5432`, and **never retries the DB** → stuck at 503 forever. A `kubectl delete pod` (once the DB
  was Ready) fixed it instantly. This is a DISTINCT post-unpark trap from the Kyverno/admission one `up` already
  handles (that's "0 pods created"; this is "pod created, stuck not-Ready on a DB that wasn't up yet"). **Fixed
  at the source:** `platctl up` now runs `recoverStartupOrderedDBClients` (PR #1105) — waits (bounded) for CNPG
  DBs to be Ready, then restarts any pod that's scheduled, not-Ready, non-CNPG, non-Job, in a namespace whose DB
  is now Ready, AND started before the DB became Ready. So future unparks self-heal this. **Other post-unpark
  observations (all pre-existing / self-resolving, NOT regressions):** `argo-rollouts` + `prometheus-operator`
  (preprod) briefly `0/1` — they hit Cilium CNI `429 putEndpointIdTooManyRequests` during the fresh-node
  bring-up storm and self-recovered after a restart within ~1-2 min (post-unpark node-storm transient; don't
  chase). `triage-demo/checkout` CrashLoopBackOff — `dial tcp payments-db:5432: connection refused`, but there
  is **no `payments-db` deployed** in that namespace (broken demo, 6d old; NOT a DB-ordering victim — it has no
  CNPG DB, so the new recovery correctly ignores it). preprod `falco` DaemonSet `1/2` — a 100m pod can't fit on
  preprod's CPU-packed small `t4g.large` nodes (18d standing capacity issue). **Gotcha reinforced:** the stale
  static `AWS_ACCESS_KEY_ID/…SECRET…/…SESSION_TOKEN` env vars bit a verification `kubectl` again (I forgot the
  `unset` on one command → `ExpiredToken`); the guard is: `unset` all three in the SAME shell command as any
  `aws`/`kubectl` call. **Verify-pod-readiness lesson:** judging unpark health by node/nodegroup/Karpenter state
  alone MISSES stuck workloads — always sweep for pods that are `Running` but `0/1` Ready (not just non-Running),
  and distinguish live gaps from finished Job pods (`Completed`/`Error` on a CronJob pod ≠ a live problem).

- **2026-06-27 (same unpark) — the hub Mimir QUERY PATH was silently degraded: ALL queries via the mimir
  gateway returned EMPTY (raw metrics + recording rules), while the mimir-querier served them fine directly.**
  Found while debugging per-app SLOs (chased a phantom "ruler write-back" bug — the recording rules were actually
  fine; `cortex_prometheus_last_evaluation_samples` > 0, querier returned the series). Root cause: the post-unpark
  **gossip-ring DNS-resolution failures** (CoreDNS gap; `memberlist failed to resolve mimir-gossip-ring ...
  connection refused` in the query-frontend log) left the **query-frontend degraded**, AND the API gateway's
  nginx held a **stale upstream** to it. Symptom signature: `mimir-querier.observability.svc:8080/.../query`
  returns data but the `mimir-gateway` (or `preprod-mimir.aws.refplat.org`) returns empty — and 16 queriers are
  "connected" so it *looks* healthy. **FIX:** restart the query path — `kubectl delete pod -l
  app.kubernetes.io/component=query-frontend` (+ `=query-scheduler`), restart the querier, THEN restart the **API
  gateway by name prefix `mimir-gateway-`** (it caches its upstream — the frontend-direct works before the gateway
  does). ⚠️ GOTCHA: `-l app.kubernetes.io/component=gateway` ALSO matches `mimir-store-gateway` (a StatefulSet) —
  don't bounce the store-gateway by accident; select the API gateway by name. **Post-unpark watch-item: smoke-test
  a query through the mimir gateway (not just the querier), since this silently breaks the W8c canary metric gate
  - W11 too.**

- **2026-06-27 (same unpark) — Karpenter NodePool came back but its EC2NodeClass did NOT → zero workload capacity.**
  Symptom: `kubectl get ec2nodeclass` empty, `nodepool default` READY=False (NodeClassReady=False, "NodeClass not
  found"), karpenter logs `ignoring nodepool, not ready`, every product pod Pending (Insufficient cpu on the lone
  system node). **Root cause = a down/up ASYMMETRY.** `platctl down` deletes the NodePool CR (to drain Karpenter)
  but LEFT the EC2NodeClass. On `up`, `-replace=helm_release.nodepool[0]` (helm uninstall→install) then deleted the
  still-present EC2NodeClass — which carries a karpenter finalizer, so it went Terminating — while cleanly recreating
  the already-absent NodePool; the NodeClass finalized away *after* the install, so helm's release was "deployed"
  (rev 1) with the NodeClass in its stored manifest yet the cluster had none (confirmed via `helm get manifest`).
  **Durable fix (platctl):** (1) `down` now deletes the EC2NodeClass too, symmetrically, AFTER the NodeClaims drain
  (so its finalizer clears) and waits for it gone — `up` then recreates BOTH from a clean slate, no leftover to
  race; (2) `up` adds a HEALTH GATE (`assertKarpenterReady`) that polls EC2NodeClass-present + NodePool Ready=True
  before declaring the env restored (a Ready=False NodePool silently strands every pod). **Immediate unblock (the
  one that worked):** recreate the NodeClass from the release's own rendered manifest —
  `helm get manifest karpenter-nodepool -n karpenter | kubectl apply -f -` (deployer context for the write) — NOT
  another `-replace` (that uninstall→install is exactly what raced). Verified: ec2nodeclass present → NodePool
  READY=True → Karpenter provisioned 2 nodes → the stranded alpha-shop-prod pods scheduled.

- **2026-06-27 — PARK (overnight) then UNPARK (platform + preprod). ✅ Both cycled — but the unpark EXPOSED a
  latent verify-images bug (the real lesson).** PARK: `platctl down --env <env> --yes` each — the **classifier
  blocked it repeatedly** ("possibly-destructive `down`", "`--yes` bypasses confirmation") until an explicit
  emphatic go ("scale down no matter what"). Confirmed `desiredSize=0` both via the EKS API; also manually
  **stopped the 2 SSM bastions** (`i-094…` preprod / `i-04c…` platform — out of platctl scope) and verified
  `ec2 describe-instances` = 0 running for true cost-zero. UNPARK: `platctl up` auto-handled NodePool + cross-vpc-dns
  (as 2026-06-26); started the bastions back. **THE failure:** every product pod was stuck post-unpark — the agent's
  Deployment at `0/1`, RS `FailedCreate = mutate.kyverno.svc-fail denied`, because cosign verify-images couldn't
  read the image sig from ECR. Root cause was a **latent bug**, not unpark damage: the platform `policy` unit never
  passed `ecr_account_id` → `kyverno-ecr` ECR ARN was account-less (`…us-east-1::repository/team-*`) → zero ECR
  access; masked because the agent pod ran continuously, exposed by the first fresh admission. Wasted a detour
  restarting Kyverno (no help — IAM gap ≠ stale creds). Fix: `ecr_account_id = account_ids["platform"]` on the unit
  (platform PR #874) + **targeted** apply of `aws_iam_role_policy.kyverno_ecr` (avoided bundled pre-existing
  policies-chart drift) + delete the stuck RS. Separately, the agent's first post-unpark pod booted during the
  CoreDNS gap → `directory.Open` timed out → directory disabled → needed a **pod delete** (rollout-restart was
  ArgoCD-reverted) to reconnect once DNS/ESO were healthy. Final confirm: `directory: connected — 1 linked person
  projected`. Net: unpark itself is smooth now; budget time for *latent admission/IAM bugs* surfacing on the first
  fresh pod admissions.

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
