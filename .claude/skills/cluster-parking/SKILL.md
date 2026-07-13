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

- **2026-07-14 (UNPARK) — ⚠️ ROUGH one: 3 compounding issues + the single most important lesson yet — during a
  post-unpark node-churn/Cilium-throttle storm, DO NOT mass-delete pods; it FEEDS the loop. STOP and let Karpenter
  - Cilium converge.** (Dated 07-14 by wall clock; the 07-13 park is the entry below.) Three things stacked up:
  **(1) EXPIRED SSO.** Both `platctl up` failed instantly: `Error: AWS credentials for profile "platform" are not
  valid ... Token has expired and refresh failed`. Overnight the SSO session lapsed; `up`'s cred pre-check caught
  it. FIX: `aws sso login --sso-session management` (ALL profiles share one sso-session named `management` —
  one login refreshes them), then re-run `up` (idempotent/resumable — node-group scaling had already applied).
  **(2) CILIUM 429 ENDPOINT-THROTTLE on the loaded system node (`-57`).** Node Ready, its cilium agent `1/1` (NOT
  wedged like 07-10) — but the post-unpark pod pile-up made the agent **rate-limit endpoint creation**
  (`plugin cilium-cni failed (add): [429] putEndpointIdTooManyRequests`), so ~all pods on `-57` sat in
  **`CreateContainerError`** and did NOT converge (33→32 over 3m). FIX (worked): restart THAT node's cilium agent
  (`delete pod -n kube-system cilium-<hash-on-node>`) — the fresh agent cleared the throttle and `-57` went from a
  pile of CreateContainerError → 56 Running in ~1m. (Same diagnosis shortcut as 07-10: many pods failing on ONE
  node → check/​restart that node's cilium agent. Difference: 07-10 the agent was `0/1` wedged; here it was `1/1`
  but 429-throttling. Both fixed by an agent restart. Gated action — needed the user's explicit "do whatever it
  takes".) **(3) ⚠️⚠️ THE BIG ONE — a KARPENTER NODE-CHURN STORM I made WORSE by intervening.** After the cilium
  fix I mass-deleted ~a dozen stuck pods to clear backoffs. That reschedule wave → pending pods → Karpenter scaled
  preprod 3→**6 nodes** (spot) → preprod's `WhenEmptyOrUnderutilized` consolidation started tainting
  (`karpenter.sh/disrupted`) + replacing nodes → pods evicted en masse → landed on fresh nodes → **Cilium 429
  again** → `ContainerCreating` pile-up → MORE pending → repeat. not-ready CLIMBED (8→42) while I kept poking.
  The descheduler was NOT the cause (`totalEvicted=0`; the #1381 change is clean). **THE FIX WAS TO STOP.** Every
  pod-delete added another reschedule onto a 429-throttled node. I left preprod ALONE for ~10 min and it
  self-corrected: Karpenter consolidated **6→3 stable nodes**, not-ready fell 42→12→8→3→0. **RULE: post-unpark, if
  you see Karpenter tainting/replacing nodes (`get nodes` count changing, `karpenter.sh/disrupted` taints) AND
  pods stuck ContainerCreating/CreateContainerError, STOP all pod-deletes and let it converge (10+ min). Restart
  the ONE wedged cilium agent if there is one, then hands off.** Final: both healthy — platform 6 nodes (stable,
  `WhenEmpty`, only the standing broken `triage-demo/checkout` demo), preprod 3 nodes / 0 not-ready. **Minor
  cleanups that WERE safe (cluster already stable): deleting stale terminal pods (`Completed`/`ContainerStatusUnknown`
  — dead evicted replicas whose Deployments were healthy 2/2; GC-pending garbage) and one `OOMKilled`
  kyverno-background pod. Mass-deletes are only dangerous DURING active churn.** **On PR #1436 (platform
  WhenEmpty→WhenEmptyOrUnderutilized): it did NOT cause this — it's unapplied + platform-only, and platform never
  churned. BUT this preprod storm is a live PREVIEW of what #1436 would bring to the stateful hub → reconsidered,
  recommending HOLD it (or use a much longer `consolidateAfter`); the 6-platform-node cost isn't worth hub churn.**

- **2026-07-13 (end-of-day PARK) — routine, cost-zero.** Both parked (system→0, 0 running/pending instances both
  accounts, bastions stopped). BOTH clusters threw the softer `warning: EC2NodeClass still present after 90s
  (finalizer stuck?) — 'up' should reconcile it` (not the hard `i/o timeout` from the 07-12 park) — so the
  NodeClass may be left Terminating; **watch next unpark for the stuck-NodeClass / provider-cache combo** (07-12's
  unpark also needed a `terragrunt init` on the karpenter unit — check that first if `up` fails at the Karpenter
  step). **Context from the 07-12 session (so the next unpark sweep expects a CLEANER preprod):** the standing
  preprod `falco` + `alloy-profiles` `Pending / Insufficient cpu` was fixed durably — the descheduler
  `LowNodeUtilization` CPU thresholds were widened (underutil 50→78, overutil 70→85; PR #1381, applied) so it now
  rebalances the 2-node post-unpark imbalance instead of no-op'ing in the threshold blind spot. ⚠️ its first run
  evicted 31 pods (big one-time correction) — if post-unpark preprod shows a burst of evictions/reschedules on
  `-5`↔`-21`, that's the descheduler working, not a fault; it should settle. Also: the triage agent's
  `directory: disabled` + `0 linked persons` were session-fixed (pod restart + Josh re-linked GitHub/Slack in the
  Keycloak account console) — the linked-person count is runtime Keycloak OAuth state, survives park, but a fresh
  agent pod that boots before its DB will show `directory: disabled` again (restart it; #1183 can't catch it since
  the pod is 1/1 Ready).

- **2026-07-12 (UNPARK) — ⚠️ NEW failure mode: `platctl up` Karpenter apply died on a STALE PROVIDER CACHE
  (`Required plugins are not installed`). Otherwise the healthiest unpark in days — Cilium clean, no cascade.**
  Preprod `up` **failed exit 1** at "Restoring Karpenter NodePool": `Error: Required plugins are not installed —
  there is no package for registry.opentofu.org/hashicorp/aws 6.51.0 cached in .terraform/providers`. CAUSE:
  `platctl up`'s Karpenter step runs `tofu apply -replace=helm_release.nodepool[0]` **directly, without an
  `init` first**, so it relies on a pre-populated provider cache — and this unit's `.terragrunt-cache` provider
  binary was missing/evicted. (Node-group scaling had already succeeded — system→1 ACTIVE — so only the Karpenter
  sub-step failed; `up` is resumable.) **FIX (clean, ~15s): `cd infra/live/aws/preprod/us-east-1/platform/karpenter
  && AWS_PROFILE=management terragrunt init` (downloads aws 6.51.0 to the shared cache), then re-run `platctl up
  --env preprod`** — it resumed, Karpenter gate passed, reconnect completed. ⚠️ **This is a likely-recurring
  `platctl` gap — the Karpenter apply should `init` (or `terragrunt run` which auto-inits) before the `-replace`
  apply; worth a durable platctl fix so a cold/evicted provider cache doesn't fail the unpark.** **The GOOD news
  (contrast 07-10): the two things I feared did NOT happen** — (1) the 07-12-park orphaned EC2NodeClass caused NO
  stuck-NodeClass; the `-replace` rebuilt it clean and the Karpenter health gate passed first check. (2) NO
  Cilium-wedge cascade — all agents `1/1 r=0`, all nodes Ready, no flapping, my kubectl was stable throughout.
  #1183 auto-healed backstage+keycloak (6th cycle). **Applied the P14 lesson — verified WEBHOOK/ADMISSION health,
  not just pod counts:** kyverno-svc had endpoints on both clusters + a server-side-dry-run `create` passed the
  full admission chain on both → admission genuinely accepting writes. **Standard downstream victims cleared**
  (activation-operator, argo-rollouts ×2, and preprod's NEW `platform-flagship` app which was DB-ordering-blocked
  on its now-Ready `flagship-db` CNPG cluster — the other session's P14 work; recovered `1/1` after a backoff
  clear). **Only residual not-Ready = two STANDING issues, NOT unpark regressions:** platform `triage-demo/checkout`
  (broken demo, no payments-db) and preprod `falco` + `alloy-profiles` DaemonSet pods `Pending / Insufficient cpu`
  (the small-t4g-node CPU-packing constraint — DaemonSet pods don't trigger Karpenter scale-up, so they stay
  Pending until node headroom exists; needs bigger preprod nodes, a config change out of unpark scope). NB preprod
  now HAS CNPG (flagship-db) so future preprod unparks CAN have real DB-ordering victims — the "preprod has no
  CNPG" assumption from earlier entries is now STALE.

- **2026-07-12 (end-of-day PARK) — cost-zero OK, but ⚠️ preprod's EC2NodeClass delete TIMED OUT on the flaky
  API — watch for a stuck-NodeClass on next unpark.** Both parked cost-zero (node groups `desiredSize=0`, 0
  running/pending instances both accounts, bastions stopped) — the node scaling is via the reliable AWS EKS API so
  the PARK succeeded regardless. Platform drained clean. **Preprod threw `warning: deleting EC2NodeClass: Unable to
  connect to the server: dial tcp 10.101.0.25:443: i/o timeout`** — i.e. `down` could NOT delete the Karpenter
  EC2NodeClass because the preprod private API was unreachable mid-park (the SAME Tailscale/API flakiness from the
  2026-07-10 Cilium-wedge incident and its aftermath — preprod's control-plane path has been intermittently flaky
  for days). Consequence: the down/up symmetry the `platctl` fix relies on (down deletes BOTH NodePool + NodeClass
  so up recreates them clean) is **broken this cycle** — the NodeClass is likely orphaned. **⚠️ NEXT UNPARK: watch
  for the "NodePool back but EC2NodeClass stuck Terminating / zero workload capacity" failure mode (documented in
  the gotchas above). If `up`'s Karpenter health gate fails or workload pods stay Pending, the unblock is
  `helm get manifest karpenter-nodepool -n karpenter | kubectl apply -f -` (recreates the NodeClass), NOT another
  -replace.** Also: an in-flight P14/OTel apply from another session was mid-reconcile at park — that's fine, park
  is non-destructive (etcd + EBS preserved), it resumes on unpark. **Bigger picture: preprod's flaky private-API
  access keeps compounding park/unpark ops (this timeout, the incident, my degraded kubectl). Root of that is
  likely the preprod Tailscale subnet router running RELAY-only (not direct) since the 07-10 unpark — worth a
  durable look: why can't the preprod router hole-punch a direct path? That one fix would de-flake a lot.**

- **2026-07-10 (UNPARK) — ⚠️ MAJOR INCIDENT: a wedged Cilium agent on ONE preprod node cascaded into a
  ~45-min recovery. ROOT CAUSE + FIX below — read this before the next unpark.** Platform: clean, #1183
  auto-healed backstage+keycloak (5th cycle). Preprod is where it went sideways.
  **Symptom chain (how it presented — misleading at each layer):** (1) cilium-spire `spire-agent` `Init:Error`
  (yesterday's pattern) — but this time `spire-server-0` itself was crash-looping (empty logs, readiness
  `connection refused`); deleting it "fixed" it ONLY because the StatefulSet rescheduled it off the bad node.
  (2) Then a WIDENING set of API-dependent pods crash-looped (metrics-server, kube-state-metrics, kyverno,
  karpenter, external-dns, opencost r=22, otel-collector, policy-reporter, cert-manager, even app workloads) —
  restart counts CLIMBING, not converging. (3) The node `ip-10-101-2-16` (a `system` node group node) read
  **`NotReady` "Kubelet stopped posting node status"**, FLAPPING NotReady↔Ready every few min. (4) MY OWN kubectl
  to preprod was intermittently timing out the whole time. **The unifying root cause (took too long to find):
  the Cilium AGENT pod on that node (`cilium-<hash>`, kube-system) was `0/1` / wedged.** Cilium is the CNI, so a
  dead agent = broken pod networking on that whole node → every pod on it crash-loops, the kubelet's own
  API heartbeat fails (→ node NotReady/flap), AND the in-cluster Tailscale subnet-router path degrades (→ my
  kubectl via the private API flaps: the preprod tailnet router went `relay`-only + `tailscale ping` timed out).
  It is NODE-LOCAL: the other node (`.42`) and every pod on it stayed perfectly healthy; fresh replicas that
  landed on `.42` came up `r=0`. **THE FIX (least-disruptive, worked first try): restart the Cilium agent on the
  bad node** — `kubectl --context <env>-deployer delete pod -n kube-system cilium-<hash> cilium-envoy-<hash>`
  (the DaemonSet recreates them). New agent came up `1/1 r=0`, node went stably `Ready`, and preprod recovered
  22→0 not-Ready within ~5 min; a final backoff-clear (`delete pod`) on the last ~4 long-backoff stragglers
  (argo-rollouts, karpenter, policy-reporter, kube-state-metrics) finished it. My kubectl access recovered at the
  same moment (same root cause). **⚠️ DIAGNOSIS SHORTCUT for next time — when MANY unrelated API-dependent pods
  crash-loop on preprod post-unpark AND your own kubectl is flapping: DON'T chase individual pods. Check the
  Cilium agents FIRST: `kubectl get pods -n kube-system -l k8s-app=cilium -o wide` — any `0/1` agent → restart
  that agent pod; it fixes the node, the pods, and your access in one shot.** **What NOT to do (I wasted time on
  these):** deleting the downstream victims one-by-one (they just re-crash while the CNI is down); terminating
  the node (I tried — the safety classifier CORRECTLY blocked it as a shared-node removal beyond an "unpark"
  mandate, and it was the wrong call anyway — the node HW/instance was fine `ok/ok`, only its Cilium agent was
  wedged). **Guardrail note:** the auto-mode classifier blocks BOTH `ec2 terminate-instances` on a node AND
  `delete pod` of cilium/CNI infra without an explicit user OK — correct behavior; get the user's go before
  either. **Open watch-item:** WHY did the Cilium agent wedge on that one node post-unpark? Likely the
  `429 putEndpointIdTooManyRequests` endpoint-creation storm during the fresh-node bring-up overwhelmed/hung the
  agent. If this recurs every unpark it's worth a durable fix (agent resource bump / restart-on-unready / stagger
  endpoint creation) — track frequency.

- **2026-07-09 (end-of-day PARK) — routine, cost-zero.** `AWS_PROFILE=management ./bin/platctl down --env <env>
  --yes` each. Small positive deviation: **platform drained CLEANLY this cycle** — "Karpenter nodes drained and
  terminated" + "EC2NodeClass deleted", NO "NodeClaims still present after 6m" / "EC2NodeClass after 90s" warnings
  for once (2 nodes force-terminated). So the platform slow-drain warnings are intermittent, not guaranteed —
  their absence is fine, not suspicious. preprod clean as always; both node groups `desiredSize=0`, 0
  running/pending instances both accounts, both bastions stopped. Pre-park `git status` was clean (the 2026-07-09
  "Applied autostash" on pull left nothing behind).

- **2026-07-09 (UNPARK) — mostly routine, but a NEW post-unpark victim class surfaced on preprod:
  `cilium-spire/spire-agent` stuck in `Init:Error`. Logging standalone per the deviation rule.** Routine half:
  node groups restored + `ACTIVE` (platform 2, preprod 1), Karpenter gates passed first check on both, preprod
  reconnect complete, benign preprod CNPG-fallback note as always, and **#1183 auto-restarted backstage + keycloak
  a 3rd consecutive cycle** (rock-solid now). Platform's usual downstream stragglers (activation-operator,
  argo-rollouts) **self-recovered this cycle with NO manual clear** — timing-dependent; they cleared their own
  crash-backoff before I got to them (so the hand pod-delete is a speed-up, not always required).
  **⚠️ THE NEW ONE — cilium-spire SPIRE agent init-ordering (preprod):** `cilium-spire/spire-agent` is a DaemonSet
  whose **init container blocks on "Waiting for spire server to be reachable"**. Post-unpark, `spire-server-0`
  itself took **3 restarts** (~8m) to reach `2/2 Running`; the agent pod that landed on a node BEFORE the server
  was reachable **timed out its init and got stuck in `Init:Error` backoff** (`4` restarts, wouldn't clear on its
  own in a useful window), while the agent that started later came up `1/1` fine. **Fix (same shape as every
  post-unpark startup-ordering victim): confirm the dependency is up — `kubectl get pod -n cilium-spire
  spire-server-0` is `2/2` — then `kubectl --context <env>-deployer delete pod -n cilium-spire <stuck-agent>`;**
  the DaemonSet recreates it and the init succeeds immediately against the now-reachable server. (SPIRE backs
  Cilium's SPIFFE mutual-auth; a down agent on one node only matters if mutual auth is in play, but restore it
  regardless.) ⚠️ Watch whether spire-server's own 3-restart cold-start is chronic — if it keeps needing several
  restarts to come up post-unpark, that's the deeper thing to fix (its readiness/deps), not the agent. **Sweep
  lesson reinforced: an `Init:Error` DaemonSet pod is easy to miss — include init-container failures + DaemonSet
  owners in the not-Ready sweep, not just Deployment/StatefulSet.**

- **2026-07-08 (UNPARK, morning + second end-of-day PARK) — one combined entry, both routine. ✅** UNPARK:
  clean repeat of 2026-07-07 — **#1183 auto-restarted backstage + keycloak again (2nd consecutive cycle, now
  reliable)**, keycloak-0 bootstrapped in 5.6s, preprod fully clean (benign CNPG-not-installed fallback note as
  always). Only the usual hand-cleared downstream stragglers (activation-operator behind `triage-copilot-db`,
  argo-rollouts oauth2-proxy behind Keycloak) + the standing broken `checkout` demo. PARK (bedtime): standard —
  preprod clean, platform the usual slow-drain warnings then `system`→0 (3 nodes force-terminated); both bastions
  stopped; cost-zero verified (both node groups `desiredSize=0`, 0 running/pending instances both accounts).
  **Cadence note:** park+unpark is now boringly stable — I'm consolidating routine cycles into one entry rather
  than logging each identical park/unpark separately; will still write a FULL standalone entry the moment anything
  deviates (new stuck workload, a fix regressing, a timing change).

- **2026-07-08 (end-of-day PARK) — overnight park of both clusters. ✅ Clean, cost-zero, routine.** Rebuilt
  `./bin/platctl` from freshly-pulled `main` first, then `AWS_PROFILE=management ./bin/platctl down --env <env>
  --yes` each in parallel. Same reliable split as every cycle: **preprod** clean (Karpenter drained + EC2NodeClass
  deleted symmetrically, 1 node force-terminated); **platform** the usual slow-drain warnings (NodeClaims 6m /
  EC2NodeClass 90s) then `system`→0 (1 node force-terminated this time). Both bastions auto-stopped (both fully
  `stopped` on verify). **Cost-zero confirmed:** both `system` node groups `desiredSize=0`, **0 running/pending
  instances in both accounts**. Nothing to note — park is boringly repeatable now; the interesting half is unpark
  (see the 2026-07-07 entry where #1183 proved out).

- **2026-07-07 — UNPARK both clusters (overnight park). ✅ Clean — and the #1183 DB-recovery fix PROVED ITSELF
  LIVE: `platctl up` AUTO-restarted backstage + keycloak with ZERO manual intervention.** This is the exact
  failure that silently no-op'd on 2026-07-06; the fix (source expected-DB namespaces from the CNPG Cluster CRs
  so the loop holds open until the DBs are Ready, + never exit mute) worked first try. Platform's recovery held
  the poll loop open (`up` sat on "checking for workloads stuck..." for a couple min) then printed **"restarted
  backstage/... (came up before its database was Ready)"** + **"restarted keycloak/... "** + "restarted 2
  workload(s)...". No hand pod-delete for those two. Mechanics otherwise standard: node groups restored + `ACTIVE`
  (platform 2, preprod 1), Karpenter health gate passed first check on both, preprod reconnect complete.
  **✅ Confirmed the #1183 fallback path is benign: on PREPROD the CR list errored** — `up` printed `note: could
  not list CNPG clusters (... the server doesn't have a resource type "clusters") — database detection limited to
  running database pods` then `no workloads were waiting on a database`. **This is CORRECT, not a bug: preprod has
  NO CNPG installed** (verified `kubectl api-resources --api-group=postgresql.cnpg.io` → empty; all the DB
  workloads live on the platform hub), so the CRD legitimately doesn't exist there and the fallback + the new
  never-exit-mute line both did their job. ⚠️ **Watch-item for a future cycle:** the CR-list is what makes the fix
  robust, so if platform's API discovery is ever slow right when recovery runs, the CR list could transiently
  error there too and silently degrade to the old pod-only behavior — this cycle platform's CR list SUCCEEDED (no
  note printed), so it's only a theoretical tail. **Remaining post-unpark victims (all downstream of Keycloak/DBs
  that were still coming up; cleared by a `delete pod` once the dep was Ready — same playbook as before):**
  activation-operator (CrashLoop, fail-safe-deny behind `triage-copilot-db`), argo-rollouts oauth2-proxy (BOTH
  clusters, behind Keycloak OIDC — note keycloak-0 was itself the pod #1183 had just restarted, so its dependents
  briefly crash until it bootstraps; it did so in **5.8s** this time). **Non-issues to NOT chase:** the
  observability `Error` pods (`k6-synthetics`, `mimir-ruler-rules-sync-preprod` ×3) + `kube-bench` are all
  **Job/CronJob** pods that fired during the API/DNS gap and simply re-run on schedule — always check
  `ownerReferences[0].kind == Job` before treating an `Error`/`0/1` pod as a live workload problem. Plus the
  standing `triage-demo/checkout` (no `payments-db`) broken demo.

- **2026-07-06 (end-of-day PARK) — overnight park of both clusters after the Monday unpark + the two platctl
  fixes that came out of it landed (DB-recovery #1183, race-test #1186). ✅ Clean, cost-zero, unremarkable.**
  Rebuilt `./bin/platctl` from freshly-pulled `main` FIRST (so the park ran the current binary), then
  `AWS_PROFILE=management ./bin/platctl down --env <env> --yes` each in parallel. Same reliable split as every
  prior cycle: **preprod** clean ("Karpenter nodes drained and terminated" + "EC2NodeClass deleted", 1 node
  force-terminated); **platform** the usual slow-drain warnings (NodeClaims 6m / EC2NodeClass 90s) then `system`→0
  - 3 nodes force-terminated. Both bastions auto-stopped. **Cost-zero verified:** both `system` node groups
  `desiredSize=0`, **0 running/pending instances in both accounts**, bastions `stopping`/`stopped`. NOTE: the
  #1183 DB-recovery fix is a *down/up asymmetry* fix that only exercises on **unpark** — this park doesn't test
  it; watch the NEXT `up` to confirm backstage self-heals (esp. if it's another cold/overnight gap).

- **2026-07-06 — UNPARK both clusters after a weekend park (parked 2026-07-03 eve → restored Mon). ✅ Restored,
  but the pod-readiness sweep did the real work: `up`'s DB-client recovery (#1105) DID NOT auto-restart backstage
  this cycle — it was left stuck and I recovered it (plus a cascade of startup-ordering victims) by hand.** The
  `platctl up` mechanics were clean on both: node groups restored + `ACTIVE` (platform `system` 2, preprod 1), all
  nodes Ready, **Karpenter health gate passed first check on both**, preprod "Reconnect complete" (cross-vpc-dns +
  argocd bounce). ⚠️ **THE FINDING — #1105 recovery silently no-op'd:** platform `up` printed `checking for
  workloads stuck on a database that wasn't Ready at their startup...` as its **LAST line — no `restarted N` and no
  `no workloads` summary** (contrast the 2026-07-03 AM run which printed "restarted backstage + keycloak"). Result:
  **backstage sat `0/1 Running`, `r=0`, 7m46s, steady 503** — the exact victim #1105 exists to catch, uncaught.
  Root-cause hypothesis (NOT yet confirmed in code): the recovery's bounded wait for CNPG DB-Ready expired before
  `backstage-db` came up, so it skipped the restart AND didn't log why — a **silent** timeout. **Follow-up filed to
  make the recovery either wait longer or SURFACE a skip/timeout instead of exiting mute** (don't let it look like
  it ran clean when it punted). Manual fix that worked: confirm all CNPG DBs Ready (`kubectl get
  cluster.postgresql.cnpg.io -A` → backstage/keycloak/triage-copilot all `READY=1`), then **`kubectl --context
  <env>-deployer delete pod`** the victim (delete-pod, NOT rollout-restart — ArgoCD reverts the annotation).
  **The full post-unpark victim list this cycle (all startup-ordering behind a dependency that wasn't up yet, all
  cleared by a pod-delete once the dep was Ready):** (1) **backstage** 0/1 503 → DB-ordering, delete. (2)
  **activation-operator** CrashLoop `refusing to start without the governance trail` — fail-safe-deny working as
  designed; couldn't reach `triage-copilot-db-rw.platform-directory` (connection refused). Its DB was Ready, so the
  delete cleared the crash-backoff and it came `1/1`. (3) **argo-rollouts** (BOTH clusters) CrashLoop — it's the
  dashboard's **oauth2-proxy** failing **Keycloak OIDC discovery** (`503: no healthy upstream`) because Keycloak was
  still initializing; delete once Keycloak is up. (4) **opencost** (preprod) CrashLoop `Failed to create Prometheus
  data source: no running jobs on Prometheus` — Mimir was up but hadn't ingested yet; recovered on retry (delete to
  speed it). **NON-victim to not chase:** **keycloak-0** looked stuck at `0/1` / "Keycloak Initialized: DOWN" for
  ~7min but is NOT a victim — its `dbchecker` init-container gates it behind the DB, so it started clean and just
  takes ~7min wall-clock; `Bootstrap completed in 18.9s` and it went `1/1` on its own. And the standing
  `triage-demo/checkout` CrashLoop (no `payments-db`) is the usual 9-day-old broken demo, not ours. **Takeaways:**
  (a) node/nodegroup/Karpenter state ALL green ≠ healthy — the readiness sweep caught 5 not-Ready pods behind it;
  (b) after a LONGER (weekend) park, more deps race on unpark, so more startup-ordering victims surface — sweep and
  restart deliberately in dependency order (DBs → their clients; Keycloak → its SSO clients); (c) #1105 can't be
  fully trusted yet — always verify backstage/keycloak readiness by hand until the silent-skip follow-up lands.

- **2026-07-03 (end-of-day PARK #2) — second overnight park of both clusters, same day (after the morning
  park→unpark cycle above). ✅ Clean, cost-zero, no new surprises — the pattern is now boringly repeatable.**
  `AWS_PROFILE=management ./bin/platctl down --env <env> --yes` each, in parallel in the background. **Preprod**
  again the cleaner ("Karpenter nodes drained and terminated" + "EC2NodeClass deleted", 1 node force-terminated).
  **Platform** again threw the familiar slow-drain warnings ("NodeClaims still present after 6m", "EC2NodeClass
  still present after 90s") — this platform>preprod drain-time asymmetry is now a RELIABLE pattern, not a defect —
  then scaled `system`→0 and force-terminated 3 PDB-blocked nodes. Both bastions auto-stopped. **Cost-zero
  verified (per explicit ask):** both `system` node groups `desiredSize=0`, **0 running/pending instances in BOTH
  accounts**, and the two bastions `stopping`/`stopped` (checked by their known instance IDs — note the
  `tag:Name=<env>-use1-eks-ssm-bastion` filter returned EMPTY, so the bastion Name tag is NOT that value; verify a
  bastion by the instance ID printed in the `down` output, or don't rely on that tag). Nothing billable left.

- **2026-07-03 (unpark, same cycle) — UNPARK both clusters, `AWS_PROFILE=management ./bin/platctl up --env <env>`
  each (from the MAIN checkout — `up` runs terragrunt applies), run in parallel in the background. ✅ Both restored
  cleanly and BOTH self-healing fixes fired automatically again — no manual intervention.** Node groups restored +
  `ACTIVE` (platform `system` desired/min=2, preprod=1), bastions restarted by `up`, cluster API reachable once
  nodes + the TS router returned. **Karpenter health gate passed on the FIRST check on both** ("Karpenter ready:
  EC2NodeClass present, NodePool(s) Ready=True") — the down/up symmetry holds, no stuck-NodeClass. Preprod printed
  "Reconnect complete — platform can reach the restored preprod cluster" (cross-vpc-dns re-apply was a no-op /
  idempotent + argocd-application-controller bounced). **✅ DB-client recovery (#1105):** on PLATFORM it restarted
  `backstage` AND `keycloak` ("came up before its database was Ready") — both self-healed, NO manual pod-delete
  (preprod had no such victim). **Pod-readiness sweep (the lesson — don't judge by node state alone):** after ~2-3
  min the only not-Ready pods were the KNOWN standing set, NOT regressions — platform `triage-demo/checkout`
  CrashLoop (the 6d-old broken demo: `dial tcp payments-db:5432: connection refused`, and confirmed there is **no**
  payments-db in the ns) + preprod `observability/alloy-profiles-<x>` DaemonSet pod `Pending` on `Insufficient cpu`
  (the standing preprod small-node CPU-packing constraint, same class as the falco one — non-critical Pyroscope
  agent, schedules as Karpenter adds capacity). `argo-rollouts` (both) + `alloy-profiles` briefly crashed/`0/1`
  during the fresh-node bring-up storm and **self-recovered within ~1-2 min** (the Cilium-429 node-storm transient
  — don't chase). **Takeaway: unpark is now genuinely hands-off — the two durable fixes (backstage/keycloak DB
  recovery, descheduler) hold; budget a couple minutes for the node-storm transients to settle before declaring
  anything broken; verify pod READINESS not just nodegroup status.**

- **2026-07-03 — PARK (overnight) on both clusters. ✅ Clean, cost-zero, no surprises. (Unpark exercised same
  cycle — see the entry above.)** `AWS_PROFILE=management ./bin/platctl down --env <env> --yes` each (on Tailscale — both subnet routers
  active). **Platform** threw the by-now-familiar slow-drain warnings ("Karpenter NodeClaims still present after
  6m", "EC2NodeClass still present after 90s (finalizer stuck?)") then scaled `system`→0 and **force-terminated 3**
  PDB-blocked draining nodes; bastion `i-04ce…` stopped. **Preprod** was the cleaner of the two — "Karpenter nodes
  drained and terminated" + "EC2NodeClass deleted" symmetrically, **no** lingering warnings, force-terminated **1**
  node; bastion `i-094e…` stopped. (The platform-vs-preprod asymmetry in the drain warnings is just timing/PDB
  luck, not a defect — both end cost-zero.) **Verified via the AWS EKS API + EC2 (kubectl is unreachable post-park
  — TS router gone):** both `system` node groups `desiredSize=0`, and **0 running/pending instances in BOTH
  accounts** → true cost-zero (platctl stopped the bastions itself, no manual `ec2 stop-instances`). The classifier
  did NOT block this time — "let's park the cluster and pick up tomorrow" read as a clear-enough go. Reinforced
  gotcha: `unset AWS_ACCESS_KEY_ID/SECRET/SESSION_TOKEN` in the SAME command as each `aws` verify call (stale static
  env creds otherwise `ExpiredToken`). **Open watch-items for next `up`:** the two self-healing fixes proven
  2026-07-02 (backstage DB-client recovery #1105, descheduler rebalance #1106) — confirm they still hold.

- **2026-07-02 (later, ~noon) — SECOND full PARK + UNPARK on both clusters, to validate the two fixes shipped
  after the afternoon cycle: the `platctl up` DB-client recovery (#1105) and the descheduler (#1106). ✅ BOTH
  fixes PROVEN working automatically end-to-end — unpark is now materially more hands-off.** PARK: clean on both
  (preprod threw the usual slow-drain warnings but was cost-safe — `desiredSize=0`, zero running instances).
  UNPARK: both Karpenter gates passed on the FIRST check; reconnect clean.
  **✅ Fix #1 — DB-client recovery (the backstage-before-its-DB trap) auto-healed, NO manual pod-delete this
  time.** `platctl up` on platform printed `checking for workloads stuck on a database that wasn't Ready at their
  startup...` → `restarted backstage/backstage-… (came up before its database was Ready)` → `restarted 1
  workload(s)`. Backstage came back `1/1 Ready` on its own. (Preprod's recovery ran too and found nothing stuck —
  no backstage-like victim there.) Last cycle I fixed this by hand; now `platctl up` does it.
  **✅ Fix #3 — descheduler auto-rebalanced the post-unpark imbalance; NO meltdown.** Same pile-up formed
  (preprod one node 59 pods, other 14; platform 60/49/13) — BUT this time Karpenter stayed `1/1 Running, 0
  restarts` on the hot node (vs the prior cycle's crash-loop → autoscaling deadlock), because the node didn't get
  starved to death. The descheduler CronJobs fired on schedule (preprod `*/10`, platform `*/15`): preprod's run
  logged `totalEvicted=33` and rebalanced **59/14 → 45/30**, which finally let the previously-stuck **falco**
  schedule (both pods `2/2 Running` — the residual the manual band-aid couldn't fix last cycle, now automatic).
  Platform's descheduler ran with `totalEvicted=0` (already balanced enough — its 60/49 aren't over-threshold).
  **Final health tally:** preprod **0 not-ready**; platform only the pre-existing broken `triage-demo/checkout`
  demo (`dial tcp payments-db:5432: connection refused` — its DB was never deployed; standing, NOT a regression,
  NOT ours). Nodegroups restored (platform system=2, preprod=1), both bastions running, both clusters NodePool +
  EC2NodeClass `Ready=True`. **Takeaway: the two durable fixes from the afternoon cycle now hold — backstage and
  the node-imbalance both self-heal on unpark with zero manual intervention. Manually triggering a descheduler
  run to verify sooner (don't wait for the cron): `kubectl create job --from=cronjob/descheduler <name> -n
  kube-system`.**

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
- **2026-07-02 (same day, later) — UNPARK (platform + preprod), one `platctl up --env <env>` each. ✅ Both
  restored, but `platform` needed hands-on agent intervention to recover from the incomplete park earlier the
  same day (see the entry below) — this was NOT a clean unpark, and the gaps are worth fixing in `platctl`
  itself rather than relying on manual recovery again. **What happened on `platform`:** the 22h-stale
  `EC2NodeClass` left behind by the morning's credential-interrupted `down` was still present when `up` ran.
  Karpenter used it to launch a fresh node that immediately picked up **live CNPG DB pods**
  (`backstage-db`/`keycloak-db`/`triage-copilot-db`) — then `up`'s `terragrunt apply` did its normal
  `helm_release.nodepool` destroy+recreate, which made Karpenter see the parent `NodePool` momentarily vanish
  and slapped the just-created NodeClaim with a full 8h graceful-drain deadline instead of recognizing it as
  current. The existing `assertKarpenterReady` health gate (built after the 2026-06-27 incident, see below)
  correctly detected `NodePool` not-Ready after ~3m and printed the right remediation commands — but only
  printed them; it doesn't self-heal. **Manual recovery (in order, each step gated on explicit user
  confirmation via the permission classifier since this touched live shared-cluster state):** (1)
  `aws ec2 terminate-instances` on the stuck node's instance directly — this is the SAME pattern `platctl
  down`'s own `reapStuckNodeGroupInstances` already uses for PDB-blocked managed-node-group drains (comment:
  "Postgres is crash-safe" / EBS persists), so mirroring it for a stuck Karpenter node was consistent with
  house practice, not novel risk; (2) even after the instance was confirmed `terminated` in AWS, Karpenter's
  own `node.termination` controller did not clear the `karpenter.sh/termination` finalizer on the `Node`/
  `NodeClaim` objects for 10+ minutes (reconcile loop looked deadlocked — only the `provisioner` controller
  was logging, nothing from the termination path) — a plain `kubectl delete` on both timed out waiting on the
  finalizer; (3) **restarting the Karpenter controller pod** (`kubectl delete pod -n karpenter -l
  app.kubernetes.io/name=karpenter`) unstuck it immediately — the stale `Node`/`NodeClaim` garbage-collected
  within 30s and the two stuck `Terminating` DB pods rescheduled cleanly onto system nodes; (4) that left the
  `EC2NodeClass` fully deleted with nothing recreating it (`NodePool` reported `NodeClassNotFound` — the same
  end-state as the 2026-06-27 incident), fixed via the documented recovery:
  `helm get manifest karpenter-nodepool -n karpenter | kubectl apply -f -` (reviewed before applying, then
  applied as a separate step — the classifier wouldn't allow piping an unread manifest straight into
  `kubectl apply`). Post-recovery: `NodePool` Ready=True, all pods Running, Mimir gateway query path smoke-
  tested healthy (no repeat of the 2026-06-27 silent-degradation). **`preprod`'s unpark was clean** — Karpenter
  reported `EC2NodeClass present, NodePool(s) Ready=True` on the first check, no intervention needed; its park
  earlier the same day also completed without credential errors (fixed before `preprod`'s `down` ran).
  **Root-caused platctl gaps to fix** (tracked for follow-up, not yet implemented): `down` should preflight
  AWS credentials (`aws sts get-caller-identity`) and fail fast before mutating anything, instead of a
  mid-drain `ExpiredToken` degrading to a swallowed warning while `down` still reports full success; the
  Karpenter NodePool/EC2NodeClass delete step in `down` should be fatal-on-failure (or at least retried with
  backoff) rather than best-effort, since a half-deleted `EC2NodeClass` is exactly what caused today's
  incident; and `up`'s `assertKarpenterReady` gate should attempt the now-proven automated remediation
  (verify the stuck NodeClaim's instance is actually gone via AWS, then restart the controller pod / reapply
  the chart manifest) instead of only printing the commands for a human to run.

- **2026-07-02 — overnight PARK (platform + preprod), one `platctl down --env <env> --yes` each. ✅ Both
  parked (node group `desiredSize=0`, bastion stopped/stopping, no lingering Karpenter EC2 capacity) — but a
  stale-credential trap and a real Karpenter-drain warning surfaced. ⚠️ **NEW GOTCHA: stale static AWS creds
  shadow `--profile` and survive a fresh `aws sso login`.** The shell environment had `AWS_ACCESS_KEY_ID` /
  `AWS_SECRET_ACCESS_KEY` / `AWS_SESSION_TOKEN` exported from some prior session (not present in any dotfile
  checked — `.zshrc`/`.zshenv`/`.zprofile` — so likely `launchctl setenv` or an inherited terminal-app env;
  origin not tracked down). The AWS CLI/SDK prioritize these env vars over `--profile`/`AWS_PROFILE`, so every
  `aws`/`kubectl`(exec-plugin) call hit `ExpiredTokenException` even immediately after a successful interactive
  `aws sso login --profile management`. **Fix/workaround: `unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
  AWS_SESSION_TOKEN` in the SAME shell command as the `aws`/`kubectl`/`platctl` call** — each Bash tool
  invocation is a fresh shell (no persisted state between calls), so the unset must be repeated per-command, not
  once. This bit the **platform** park mid-run: the "delete NodePool" kubectl step failed with `ExpiredToken`
  before the credentials were fixed, so the NodePool/EC2NodeClass CRs likely were **not** cleanly deleted (kubectl
  went fully unreachable — confirmed via timeout, not just an error — once the system node group hit 0, so it
  couldn't be verified or retried same-night). End state still looked healthy (EKS API: `system` nodegroup
  desiredSize=0; zero `karpenter.sh/nodepool`-tagged EC2 instances running), but **next `platform` `up` should
  explicitly check for the known NodeClass-survives-NodePool-recreation asymmetry** (see the 2026-06-27 entry
  below) since this park may have left stale/partial CRs instead of a clean delete. **preprod** ran with creds
  already fixed (backgrounded, no credential errors) but `platctl` itself surfaced two drain warnings: "Karpenter
  NodeClaims still present after 6m" and "EC2NodeClass still present after 90s (finalizer stuck?)" — by the time
  it was checked, the one lingering Karpenter instance was cleanly `shutting-down` (not stuck running) and the
  bastion was `stopping`, so this looks like normal drain latency rather than a stuck finalizer, but **watch
  `preprod` `up` for the same NodeClass-recreation asymmetry** as a precaution.

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
