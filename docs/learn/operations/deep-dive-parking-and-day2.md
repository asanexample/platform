# Learn: Operations — parking & day-2 recovery (deep dive)

Parking scales the worker node groups to zero overnight, non-destructively; `platctl up` restores them
and then runs a battery of recovery sweeps. Parking is where a live platform breaks and you have to read
it, so this goes deep: the exact `down` and `up` orderings, three counter-intuitive gotchas, and the day-2
recovery stories — each a real incident and the durable fix that outlived it. The
[Operations orientation](orientation.md) covers the same ground at a higher altitude (its Stops 2 and 4).

## Why park at all, and why "non-destructive" is the whole game

A reference/demo platform doesn't need to run at 3 a.m. The two clusters are the single biggest non-prod
cost lever — the [cost module](../cost/orientation.md) owns the accounting, this doc owns the mechanism —
and `platctl down --env <env>` drops ~all of their compute spend by scaling every EKS managed node group to
`desiredSize=0`, `minSize=0` via the AWS EKS API. `platctl up --env <env>` restores them. That's the pitch.
The discipline is in the word **non-destructive**.

> **Mothballing a ship, not scrapping it.** Park powers down the engines and sends the crew home — the hull,
> the cargo, and the ship's log all stay. Scrapping is `teardown`: a full destroy back to ~$0. Two different
> verbs, on purpose. **Where it breaks:** a mothballed ship is inert — nobody's aboard. A parked cluster's
> control plane keeps running (AWS bills the EKS control plane whether or not any worker exists), so every
> custom resource — Deployments, Karpenter NodePools, `XEnvironment` claims, Kyverno policies — is still
> there, reconciling nothing because there are no nodes. Scaling to zero removes only compute.

Every [EBS](https://docs.aws.amazon.com/ebs/latest/userguide/what-is-ebs.html) volume survives too —
critically the CloudNativePG ([CNPG](https://cloudnative-pg.io/documentation/current/)) Postgres databases
behind Backstage, Keycloak, and the triage agent. Postgres is crash-safe, the PVs persist, and the same
volumes re-attach when the pods reschedule on `up`. Turning off the office lights, not emptying the filing
cabinets.

The one structural fact that makes the ordering hard: there is exactly one managed node group per cluster —
`system`, which hosts the platform controllers (verified live: `aws eks list-nodegroups` returns just
`system` on both `platform-use1-eks` and `preprod-use1-eks`). All workload capacity is
[Karpenter](https://karpenter.sh/docs/) (ADR-078), and Karpenter's own controller runs inside the cluster,
on `system`. So you can't naively zero `system`: do it while Karpenter is still managing nodes and you kill
the controller mid-flight, orphaning its EC2 instances — detached from any nodegroup, still billing. Parking
has to shut Karpenter down first, cleanly, and in order.

## The `down` ordering — five steps

`NewDownCmd` in [`scale.go`](https://github.com/asanexample/platform/blob/main/cmd/platctl/internal/cli/scale.go)
runs five things in sequence. Every step earned its place because an earlier version bled.

**0. Credential preflight** (`checkAWSCredentialsForEnv`) — one cheap `aws sts get-caller-identity` before
the confirmation prompt or any mutation. It looks like paranoia until you read the 2026-07-02 incident: a
stale `AWS_SESSION_TOKEN` in the shell shadowed `--profile` (the AWS SDK prefers static env creds, and they
survive a fresh `aws sso login`), an `ExpiredToken` hit mid-drain, the failure was swallowed as a printed
warning, and `down` still reported success — leaving a half-deleted EC2NodeClass that corrupted the next
`up`. Fail fast on a dead session, before touching anything, and that whole class of incident dies at the
source.

**1. Clear `karpenter.sh/do-not-disrupt`** from stateful pods (`doDrainKarpenterNodes`). That annotation is
how CNPG databases and the observability stores opt out of Karpenter's voluntary disruption
(consolidation/drift/expiry) in steady state — but it also blocks the termination drain, so an uncleared
NodePool delete would hang forever. A park is an intentional full shutdown, so overriding the steady-state
guard is correct; the drain stays graceful — clear the annotation, don't force-kill. On `up`, the workloads'
pod templates re-add the annotation, so the protection comes back on its own.

**2. Delete the NodePool and EC2NodeClass symmetrically**, polling until the NodeClaims are gone. `kubectl
delete nodepool --all --wait=false` cascades to NodeClaim deletion in the background and returns early, so
the code polls `get nodeclaims` up to ~6 min until empty, then deletes the EC2NodeClass and waits ~90 s for
its finalizer to clear (`deleteEC2NodeClasses`). The symmetry is the scar: on 2026-06-27, `down` deleted only
the NodePool and left the finalizer'd EC2NodeClass behind, and the next `up`'s force-replace raced it into
`Terminating` → `NodeClassReady=False` → every workload pod stranded `Pending`. Delete both, from a clean
slate, and `up` recreates both with nothing to race.

**3. Scale the managed groups to zero** (`scaleNodeGroupsToZero`) — one `aws eks update-nodegroup-config
--scaling-config minSize=0,desiredSize=0` per group. EKS drains each node via a lifecycle hook that respects
PodDisruptionBudgets, which is usually good — but a PDB-blocked pod can stall a node in `Terminating:Wait`
for the ~15-min hook timeout, burning money for nothing. So `reapStuckNodeGroupInstances` gives a ~2-min
graceful window (12×10 s), then force-terminates stragglers via `ec2 terminate-instances`. Safe, because a
park is a full shutdown and EBS is crash-safe. This is the recurring "force-terminated N PDB-blocked nodes"
line in the Learnings log — platform typically reaps 3, preprod 1, and that asymmetry is PDB/timing luck, not
a defect.

**4. Stop the SSM bastion** (`setBastionPower false`) — a standing EC2 instance outside the node groups (the
SSM fallback path for private-cluster access), so true cost-zero has to stop it too. It's discovered
best-effort by its derived Name tag (`bastionName` strips `-eks` → `<cluster>-ssm-bastion`).

The operator's cost-zero check has three parts: `system` at `desiredSize=0`, zero running instances in the
account, and the bastion stopped. Confirm the first with the EKS API (see gotcha 1), never kubectl — that's
already gone.

## The `up` ordering — more than the inverse

`NewUpCmd` doesn't just undo `down`; it re-applies from source and then runs a battery of recovery sweeps.
Nine steps; the ones that carry weight:

1. **Credential preflight for both profiles.** `up` uses two: the terragrunt auth profile (e.g.
   `management`/PlatformDeployer, for the applies) and the per-account `kc.Profile` (for the kubectl calls).
   A stale session on either degrades into a mid-run `ExpiredToken`, so both get checked.
2. **Re-apply the `node-groups` unit** (`terragrunt apply`). The HCL is the source of truth, so the
   API-induced scaling drift self-heals back to the configured sizes: platform `system` 2/2/3, preprod
   1/1/2 (verified in the live `node-groups` units).
3. **Start the bastion early**, so SSM access is available while the rest comes back.
4. **Gate on the cluster API before touching Karpenter** (`waitForClusterAPI`, up to ~15 min). The karpenter
   apply uses the helm/kubernetes providers, which need the private API — fronted by the in-cluster
   Tailscale subnet router that only reschedules once the restored `system` nodes are `Ready`. Apply too
   early and it fails and orphans Karpenter's helm releases from Terraform state (a "cannot re-use a name"
   trap needing manual import, #660). On timeout it skips the karpenter apply and tells you to re-run — it
   never applies into an unreachable API.
5. **Recreate the NodePool** with `terragrunt apply -replace=helm_release.nodepool[0]`. A plain apply reports
   "0 changed" (Terraform still has the NodePool in state even though `down` deleted the live CR), so it has
   to force-replace.
6. **`assertKarpenterReady`** — poll until the EC2NodeClass exists and every NodePool is `Ready=True` (a
   `Ready=False` NodePool provisions nothing and silently strands every pod). This gate now attempts its own
   automated recovery before giving up: restart the Karpenter controller pod to unstick a deadlocked
   termination reconciler, and — if the EC2NodeClass is fully gone — recreate it from `helm get manifest
   karpenter-nodepool | kubectl apply -f -`. That codifies the manual fixes from the 2026-06-27 and
   2026-07-02 incidents.
7. **`recoverKyverno`** — restart the admission controller if a Deployment wants pods but has none (the
   fail-closed sigstore/TUF trap, gotcha 2) and surface the real `FailedCreate` if a block persists.
8. **`runReconnect`** — re-apply the platform `cross-vpc-dns` unit and bounce the platform ArgoCD controller
   (story C).
9. **`recoverStartupOrderedDBClients`** — the DB-ordering sweep (story B).

## The three gotchas

The [cluster-parking skill](../../../.claude/skills/cluster-parking/SKILL.md) header says it plainly:
park/unpark is not yet stable. Treat every gotcha as suspected-until-reconfirmed, and append a dated
Learnings-log entry after every cycle. These three are why.

**1. After parking, `kubectl` is unreachable — and that's a successful park.** Scaling to zero also kills the
in-cluster Tailscale subnet router that advertises the VPC CIDR to the tailnet, so the private EKS API
(private-only by design, ADR-010) has no in-VPC path and `kubectl` times out (`i/o timeout` to the API ENI).
Expected, not a failure. Confirm the park via the AWS EKS API instead:

```bash
AWS_PROFILE=<platform|preprod> aws eks describe-nodegroup \
  --cluster-name <env>-use1-eks --nodegroup-name system \
  --region us-east-1 --query nodegroup.scalingConfig
# -> "DesiredSize": 0
```

On `up`, kubectl works again only once the nodes and the router pod are back (minutes). The deep trap
(runbook failure mode #7): after a long park the router pod's stored Tailscale node key can go invalid →
`NeedsLogin` CrashLoop → the route never returns. Fix: delete its state secret and pod so the operator
re-mints an auth key.

**2. Unpark forces a fresh admission of every pod — a merciless integration test.** A pod that ran for days
never re-hit the admission webhooks; unpark re-creates all of them at once, exposing latent
admission-webhook/IAM bugs that were masked while pods ran continuously. The canonical case (2026-06-27): no
product workload could be created — Deployments at `0/1` with no pod, ReplicaSet `FailedCreate:
mutate.kyverno.svc-fail denied`, because cosign verify-images couldn't pull the signature from ECR. Not
unpark damage — a latent bug: the platform `policy` unit never set `ecr_account_id`, so the `kyverno-ecr`
role's ECR ARN rendered account-less and matched no repo. Invisible while pods ran; exposed by the first
fresh admission. The corollary that saves you a detour: restarting Kyverno does not fix an IAM gap — IAM is
evaluated at call-time, not cached in creds. Read the real admission error instead.

**3. Judge unpark health by pod readiness, not node/nodegroup state.** Node groups `ACTIVE`, all nodes
`Ready`, Karpenter `Ready=True` — all green, and still broken (2026-07-02): Backstage sat `0/1 Running` for
33 minutes with everything green, because it started ~17 min before its CNPG database was `Ready`, failed
every DB-backed plugin with `ECONNREFUSED`, and never retries the connection. The standing lesson: sweep for
`Running`-but-`0/1` pods, and distinguish live gaps from finished Job pods — `ownerReferences[0].kind == Job`
means a CronJob run that fired during the API/DNS gap, not a live problem. Restart in dependency order
(databases → clients; Keycloak → its SSO clients).

## Day-2 recovery stories — real failure → durable fix

Every recovery sweep in `up` was born from a specific incident. Each story runs the same play: a band-aid to
stop the bleeding, then surgery — fix the source so it can't recur.

### Story A — the node-imbalance meltdown → the descheduler (ADR-093)

The marquee 2026-07-02 incident. The scheduler places a pod on a node once and never moves it, so after
unpark the first node up absorbs nearly everything. One preprod `t4g.large` ended with 59 pods (~99% CPU
requests, 189% memory-limits) while its sibling sat at 14 (~40%). The hot node's kubelet degraded
(`NodeStatusUnknown`) and every pod on it crash-looped — including Karpenter's own controller. That's the
deadlock: the one thing that could add capacity was starved on the hot node. Capacity was never the problem
(balanced, the workload fits at ~69%/node) — pure distribution.

`kubectl delete` doesn't help (the scheduler re-pins to the same hot node). `topologySpreadConstraints`
(ADR-085) don't help either — they spread replicas of one workload, and a fleet of independent single-replica
controllers has nothing to spread against.

- **Band-aid:** `kubectl delete pod -n karpenter -l app.kubernetes.io/name=karpenter` — once Karpenter is
  `Ready` the rest self-heals, but it may reschedule onto the same hot node. Unblocks; doesn't fix.
- **Durable fix:** the [kubernetes-sigs descheduler](https://github.com/kubernetes-sigs/descheduler)
  ([ADR-093](../../adrs/093-descheduler-node-rebalancing.md), PR #1106) — a periodic CronJob running
  `LowNodeUtilization`: evict pods off over-utilized nodes so they reschedule onto under-utilized ones. It
  respects PodDisruptionBudgets, uses `nodeFit: true` so it never strands a pod `Pending`, and skips
  DaemonSet/local-storage/system-critical pods.

Live and proven on both clusters (verified this session):

```text
$ kubectl get cronjob -A | grep descheduler
kube-system   descheduler   */15 * * * *   ...   # platform (hub): calm 40/70 defaults
kube-system   descheduler   */10 * * * *   ...   # preprod
```

The threshold tuning is the teaching detail: platform runs the module defaults (underutilized 40% /
overutilized 70%, every 15 min — bigger nodes, stateful hub, fewer evictions is better). Preprod raises the
underutilized threshold to 50% (schedule `*/10`) because the incident's cool node sat at 39% — one point
under the 40% default — so it never qualified as a rebalance destination. (Module:
[`infra/modules/descheduler`](https://github.com/asanexample/platform/blob/main/infra/modules/descheduler);
live units under `platform` and `preprod`.)

> **Honest doc-drift.** ADR-093's header still reads `Status: Proposed`, and commit #1106 is tagged
> `[WIP — not applied]` — yet the CronJobs have been live on both clusters for days. The ADR and commit are
> stale versus reality; ADR-093 is really Accepted. Flagged here rather than papered over — the "secondary
> sources are leads, not proof" rule doing its job.

### Story B — DB-client startup ordering → `platctl up` self-heal (#1105 → #1183)

A CNPG database and its client both restart on unpark. If the client comes up before the database is `Ready`,
it fails every DB op and — never retrying — stays broken indefinitely. A pure ordering trap a node-health
check misses (this is gotcha 3, in code). The durable fix, `recoverStartupOrderedDBClients`, finds workloads
that (a) aren't a CNPG database pod, (b) aren't a Job, (c) live in a namespace whose CNPG database is now
`Ready`, and (d) started before that database became `Ready` — and restarts exactly those. Restart is a pod
delete, not a rollout-restart: a rollout-restart annotation would be reverted by ArgoCD self-heal. It polls
up to ~12 min — long enough for a CNPG cluster to restore from a cold weekend-parked EBS volume and elect a
primary.

Then the tell that the discipline is real — the fix had its own bug. On the 2026-07-06 cold unpark, recovery #1105
silently no-op'd: the CNPG operator hadn't yet recreated the `Cluster` CRs' pods when the check ran, so
pod-only detection saw "no database here," declared nothing to wait for, and exited mute — leaving Backstage
wedged at 503. Fixed at source in #1183 by deriving the expected-DB namespaces from the surviving `Cluster`
CRs (which outlive parking, pod or no pod), and by never exiting mute — if a client stays stuck behind a
database that never came `Ready`, it now names the victim and prints the manual finish. Proven live on the
2026-07-07 unpark: `up` auto-restarted Backstage and Keycloak with zero manual intervention. A durable fix
that fixed a bug in a previous durable fix.

### Stories C, D, E — the rest of the corpus, briefly

- **C — stale cross-VPC DNS after a preprod restore → `runReconnect` (#540).** When preprod's control-plane
  ENIs are recreated (new private IPs), the platform VPC's `cross-vpc-dns` private hosted zone still maps the
  preprod API hostname to the old IPs, so ArgoCD (on platform) dials dead IPs (`dial tcp …:443: i/o
  timeout`) and every `XEnvironment`/Product sync fails with a misleading "unable to verify permissions."
  `runReconnect` re-applies the idempotent `cross-vpc-dns` unit and restarts the platform
  `argocd-application-controller` (verified in `.platctl.yaml`'s `reconnect` block). Proven on real preprod
  unparks.
- **D — Kyverno helm orphaned from TF state → `import` + apply.** After a teardown/scale cycle the `policy`
  unit's state can lose its `helm_release.kyverno`/`policies` entries while the releases persist healthy
  in-cluster, so the next apply fails "cannot re-use a name." Recovery is a state-only `terragrunt import` of
  both releases, then plan (expect 0-destroy) → apply. Scope boundary: this is teardown-scoped — a park/unpark
  preserves TF state, so it doesn't recur on unpark, only on teardown/rebuild.
- **E — helm stuck `pending-upgrade` → delete the pending-revision secret.** An apply killed mid-helm-upgrade
  (a slow chart exceeding a foreground timeout) leaves the release wedged; every later apply fails "another
  operation in progress." Recovery: `kubectl delete secret sh.helm.release.v1.<release>.v<N>` (needs the
  deployer context, not read-only PlatformAdmin) → re-plan + apply. The durable lesson is a habit: run slow
  helm applies in the background from the start, so the foreground timeout never interrupts an upgrade.

## The durable-fix discipline

Every story is one principle (see `feedback_durable_fix_over_hotfix`): on any failure, fix the source, commit
it, open a PR. A manual unblock to restore service is fine — but you have to land the durable fix so it can't
recur.

| Failure | Band-aid (unblock now) | Durable fix (can't recur) |
| --- | --- | --- |
| Node meltdown | `delete` the Karpenter pod | descheduler (ADR-093) |
| DB-client ordering | `delete` the client pod | `up` DB recovery (#1105 → #1183) |
| Stale cross-VPC DNS | re-apply by hand | `up` `runReconnect` (#540) |
| Helm pending-upgrade | delete the revision secret | run slow applies in background |

Why the discipline is even possible here ties back to the orientation: because the platform is fully IaC +
GitOps, "fix the source" is always a well-defined action — a module edit, a `platctl` code change, a policy
change — that flows through review and reconciles automatically. There's no config drawer to hand-edit and
forget. The rebuild thesis and the durable-fix discipline are the same commitment: nothing that matters
exists only in the running cluster.

## Status — built core, maturing envelope

Parking is live and used on both clusters — clean cost-zero cycles, logged. The recovery sweeps and the
descheduler are proven: the descheduler is live on both clusters (verified this session); the #1183
DB-recovery auto-restarted Backstage and Keycloak with zero manual intervention on 2026-07-07; DNS-reconnect
has held on real preprod unparks. The core (`down`: drain → scale → bastion; `up`: restore → gates → sweeps)
is fully built. What's still maturing is the reliability envelope — each sweep was born from a specific
incident, and residual post-unpark victims still get cleaned up by hand, then durably fixed, each cycle.
Unpark is now mostly hands-off, not provably hands-off. Hence the one rule that never changes: read the
Learnings log before every park/unpark, and append to it after.

## Go deeper

- [ADR-093 — descheduler for node rebalancing](../../adrs/093-descheduler-node-rebalancing.md) (the
  meltdown, the thresholds, the alternatives) ·
  [ADR-078 — Karpenter elasticity](../../adrs/078-cluster-elasticity-karpenter.md) ·
  [ADR-085 — workload availability](../../adrs/085-workload-availability-graceful-disruption-defaults.md)
  (PDBs, topology-spread, replica floor) ·
  [ADR-010 — private EKS API endpoint](../../adrs/010-private-eks-api-endpoint.md).
- [`cmd/platctl/internal/cli/scale.go`](https://github.com/asanexample/platform/blob/main/cmd/platctl/internal/cli/scale.go)
  — every function cited here, with `scale_test.go` for the pure targeting logic.
- Runbook: [`docs/runbooks/cluster-scale-down-up.md`](../../runbooks/cluster-scale-down-up.md) — the 7 known
  failure modes and their fixes. Skill: `cluster-parking` (its Learnings log is the living incident record).
- External (all verified 200): the
  [kubernetes-sigs descheduler](https://github.com/kubernetes-sigs/descheduler) (its README documents
  `LowNodeUtilization`, `nodeFit`, and the evictor safety knobs — ~15 min);
  [Karpenter disruption](https://karpenter.sh/docs/concepts/disruption/) (`do-not-disrupt`, consolidation,
  drift — the steady-state behavior `down` overrides); Kubernetes
  [Pod disruption / PDBs](https://kubernetes.io/docs/concepts/workloads/pods/disruptions/) (why a
  PDB-blocked node stalls a drain).
