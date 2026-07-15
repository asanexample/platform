# Learn: Operations — orientation

How you actually *run* this platform — stand it up, park it overnight to save money, rebuild it from
zero, and recover it the morning it breaks — without a human remembering the order that 110 pieces have to
go in.

**Audience:** platform engineers who operate the stack (or want to understand how it's operated).
**Before you start:** [Foundations](../foundations/README.md) (what the pieces *are* — accounts, IaC, the
cluster, Cilium) makes the rest easier. A passing familiarity with Terragrunt and "a Kubernetes cluster has
a control plane and worker nodes" is enough; we'll build from there.

## The problem

The platform is ~110 Terragrunt units across two clusters and three accounts, with brutal ordering
constraints. The state backend has to exist before anything can initialize. The CNI has to be running
before a node can join. Sign-in has to be wired before the app that needs it deploys. Nobody can hold that
order in their head — and it isn't a one-time problem. You stand it up, scale it to zero every night for
cost, bring it back every morning, occasionally tear the whole thing down and rebuild it, and every so
often walk in to find it broken.

So how do you build, park, rebuild, and recover a 110-piece multi-cluster platform — repeatably, in the
right order, without a runbook nobody can execute perfectly at 3 a.m.?

## The platform is a dependency graph you can replay

`platctl`, a DAG-aware orchestrator, walks that graph: forward to **build**, in reverse to **tear down**,
to-zero-and-back to **park**, from-ash to **rebuild**. And because the graph *is* the platform — every
piece declared in git, nothing that matters living only in the running cluster — the platform is fully
reconstructable from code. Every operational failure becomes a source-level fix in the graph, not a
hand-patch that rots.

Two halves, the same commitment from two angles:

1. **Replayable.** `platctl` doesn't hardcode the order. It discovers the graph by parsing each unit's
   dependency declarations, then walks it in parallel where safe (independent units at once) but never a
   unit before its dependencies. One tool, one graph, four verbs: `bootstrap`, `teardown`, `down`/`up`
   (park), `validate`.
2. **Reconstructable, so you operate by durable fix.** Infra is IaC (OpenTofu/Terragrunt), in-cluster state
   is GitOps (ArgoCD), config secrets are committed (SOPS). "Fix the source" is always a well-defined action
   that flows through review and reconciles automatically — there's no config drawer to hand-edit and
   forget. That's what makes the durable-fix discipline (see *recover*, below) possible at all.

> **`platctl` is a build system for the whole platform.** Like `make` or Bazel builds a target graph —
> running independent targets in parallel, never a target before its inputs, and able to rebuild the whole
> thing from clean — `platctl` builds a *unit* graph and applies it the same way. Where it breaks: a code
> build is pure and instant; infrastructure has side effects, takes an hour, and can half-fail. So `platctl`
> adds what `make` lacks — a pre-flight checklist, a safe reverse for demolition, resume after a mid-run
> failure, and post-build health checks. It's a build system that can also un-build, and survive a crash
> halfway.

The tour is build, park, rebuild, recover.

---

## Build: walk the graph forward (`platctl bootstrap`)

`platctl bootstrap` walks the dependency DAG forward, applying units in waves (everything with no unmet
dependency runs at once, bounded by a concurrency limit), and stops cleanly if a unit fails — marking that
unit and everything downstream `skipped`, letting in-flight work finish, and printing a `--resume` command.
It's discovered, not scripted: drop a new `terragrunt.hcl` in and it's in the graph on the next run.

A few ordering constraints are the ones that matter:

- **The floor comes first, and it's *below* platctl.** The S3 state backend can't be created *by* something
  that needs the S3 state backend — you can't store your state in the bucket you haven't made yet. So
  `state-bootstrap` uses a *local* backend on its first apply, creates the bucket + lock table that
  every other unit then uses for state — a classic chicken-and-egg break.
  This floor (state + the SOPS KMS key) lives *outside* the environments platctl manages, so it's stood up
  once by hand and platctl never touches it.
- **Cilium first, as bring-your-own CNI.** This is the single most important ordering fact. The cluster runs
  Cilium instead of the AWS VPC CNI. A node with no CNI comes up `NotReady`, and CoreDNS can't schedule
  until *both* CNI and nodes are ready. You can't express "make the cluster, wait for an external Helm
  install, *then* add nodes" inside one module — so EKS is deliberately **split** into `eks → cilium →
  node-groups → eks-addons`, wired by dependencies. *You can't lay carpet (pods) before the subfloor
  (CNI), or move furniture in (CoreDNS) before the floor and walls (nodes) exist.*
- **Bootstrap, then lock down.** The EKS API is private-only by design — but during a from-scratch build there's no
  in-VPC path yet (Tailscale isn't up), so platctl applies EKS with the public endpoint *temporarily on*,
  then a **lockdown phase** re-applies to slam it shut (after enabling Tailscale split-DNS first, and
  refreshing the DNS records the endpoint churn invalidates). This is the only time the public endpoint is
  ever on — and platctl owns the toggle, so you never touch it by hand.

The [platctl & the DAG deep dive](deep-dive-platctl-and-the-dag.md) has the discovery mechanism, the full
ordering, the hooks, and `validate`.

---

## Park: walk the graph to zero and back (`platctl down`/`up`)

A reference/demo platform doesn't need to run at 3 a.m. **Parking** scales the EKS worker node groups to
zero overnight — dropping ~all compute cost — and restores them in the morning. The critical word is
*non-destructive*: the EKS control plane keeps running (AWS bills only the workers you removed) and every
EBS volume survives, so the CNPG Postgres databases (Backstage, Keycloak, the triage agent) come back
exactly where they left off.

> *Mothballing a ship, not scrapping it.* Park = power down the engines, send the crew home; the hull, the
> cargo, and the ship's log stay. `teardown` = scrapping. Different verbs on purpose. Or: turning off the
> office lights but leaving every filing cabinet exactly where it was.

The ordering is subtler than "call the API." Karpenter (the node autoscaler) runs *inside* the cluster, so
`down` clears the stateful-pod disruption guards, deletes the Karpenter NodePool **and** EC2NodeClass
symmetrically, *then* scales the node groups to zero (force-terminating PDB-blocked stragglers), *then* stops
the bastion. `up` is more than the inverse — it re-applies the node config, waits for the cluster API before
touching Karpenter (applying too early orphans its Helm releases), recreates the NodePool, and runs a
battery of recovery sweeps (see *recover*, below). The [parking & day-2 deep
dive](deep-dive-parking-and-day2.md) has the full choreography and the scars behind each step.

Three gotchas worth holding now, because they're counter-intuitive:

- **After parking, `kubectl` is unreachable.** Scaling to zero also kills the in-cluster Tailscale router,
  so the private API is unreachable. That's expected; you confirm a park via the **AWS EKS API**, not
  kubectl.
- **Unpark forces a fresh admission of every pod.** A pod that ran for days never re-hit the admission
  webhooks; unpark re-creates all of them, so every latent policy/IAM bug fires at once. Unpark is a
  merciless integration test.
- **Judge health by pod readiness, not node state.** Nodes `Ready`, Karpenter `Ready`, and still broken —
  because a client started before its database was up and never retried.

---

## Rebuild: from ash (`teardown` → `bootstrap`)

Because every layer is declared — infra in IaC, cluster state in GitOps, config in committed SOPS — you can
destroy the entire platform and rebuild it from zero. The rebuild runbook says it bluntly: *"data loss is
expected and acceptable — the success criterion is that the platform is fully reconstructable from code."*

> *A phoenix, not a pet.* "Cattle not pets" says don't nurse a sick server — replace it. This goes a level
> up: the *whole environment* is cattle. Reduce it to ash with `teardown`, reboot it from git with
> `bootstrap`.

This isn't aspirational — it's dogfooded. The team ran repeated overnight teardown→rebuild cycles until both
ran clean with zero manual steps (a full clean bootstrap *and* teardown, every unit), and every cycle that
found a broken step got that step fixed at the source and merged. The rebuild is a fire drill you actually
run, and it pays off four ways: disaster recovery (a region loss is a rebuild, not an archaeology dig),
drift elimination (anything in the cluster but not in git simply doesn't come back — the cycle *is* the
drift detector), proof of no snowflake state (if it rebuilds, no undocumented manual step was holding it
together), and confidence to change (cheap teardown is the safety net under every risky change).

The one unavoidable hole is the **seed vault**. You can burn the farm down and regrow it every season — as
long as the seed vault and its key survive the fire. Two resources must survive every teardown: the S3 state
backend (it holds the state the rebuild reads from) and the `platform-sops` KMS key (it decrypts the
committed config; lose it and `secrets.enc.yaml` is permanently unreadable). They're protected by living
*outside* the environments platctl tears down — it only touches `platform` + `preprod`, never the management
account — plus a belt-and-suspenders `prevent_destroy` on the KMS key.

---

## Recover: operate by durable fix (day-2)

The rebuild thesis is the happy path. Day-2 is the morning a *live* platform breaks, usually just after an
unpark. The operating principle is one rule: on any failure, fix the source, commit it, open a PR. A manual
unblock to restore service is fine — but land the durable fix so it can't recur. Band-aid to stop the
bleeding; durable fix so you never bleed there again.

The textbook case is the post-unpark node-imbalance meltdown. The scheduler places a pod on a node once and
never moves it, so after an unpark the first node up absorbed nearly everything: one node hit 59 pods /
~99% CPU while its sibling sat at 14, the hot node's kubelet degraded, and every pod on it crash-looped —
including Karpenter's own controller. Deadlock: the one thing that could add capacity was starved on the hot
node. Capacity was never the problem; distribution was.

- **Band-aid** (unblock now): `kubectl delete` the Karpenter pod so it reschedules and the rest self-heals.
- **Durable fix** (merged): the descheduler — a
  periodic job that evicts pods off over-utilized nodes so they rebalance onto under-utilized ones (PDB-safe,
  never strands a pod). Live on both clusters. "Just restart Karpenter every morning" was the band-aid; the
  descheduler is what "fix the source" looks like.

`platctl up`'s recovery sweeps are the same discipline, automated: a DB-client recovery step (restart the
clients that came up before their database) and a DNS reconnect step (refresh the cross-VPC records the
control-plane ENIs invalidate on restart, and bounce ArgoCD's stale connection). One tell that the
discipline is real: a durable fix (DB-client recovery) later turned out to silently no-op on a cold weekend
unpark — and *that* was itself treated as a bug and durably fixed. The discipline recurses. The [parking &
day-2 deep dive](deep-dive-parking-and-day2.md) walks every recovery story end to end.

---

## The honest status — proven vs still-maturing

- **Live and proven:** `platctl` (bootstrap/teardown/validate/park — all built, tested Go); parking on both
  clusters (clean cost-zero cycles); the descheduler (both clusters); the `up` DB-client + DNS recovery
  sweeps (proven on real unparks).
- **Validated offline:** full teardown/rebuild reconstructability — proven via repeated overnight cycles
  (zero manual steps). The strongest evidence for the whole thesis.
- **Still-maturing / rebuild-gated:** park/unpark is explicitly *"not yet stable"* — a living procedure whose
  Learnings log is appended after every cycle (the recovery stories are why). And a couple of cutovers
  (Keycloak identity, the v3 domain model) have only ever been verified offline — the next rebuild is their
  first real live apply.

The machinery — platctl, parking, the recovery sweeps — is built and exercised daily. The reliability
envelope is still being hardened one incident at a time, which is the durable-fix discipline doing its job.

## When it breaks — the ones you'll actually hit

- **"I parked it and `kubectl` times out."** Expected — the Tailscale router is gone. Confirm the park with
  the AWS EKS API (`describe-nodegroup` → `desiredSize: 0`), not kubectl. It returns minutes after `up`.
- **"After unpark, a Deployment has 0 pods / a `FailedCreate`."** Unpark re-admitted everything and hit a
  latent policy/IAM gap that was masked while pods ran. Restarting Kyverno won't fix an IAM gap — IAM is
  evaluated at call-time; read the real admission error.
- **"Nodes are all `Ready` but a pod is stuck `0/1`."** Judge by readiness: it probably started before its
  database and never retried. The `up` DB-client sweep handles this; manually, restart the client pod
  (not `rollout restart` — ArgoCD self-heal reverts the annotation).
- **"`platctl bootstrap` failed halfway."** It saved state — `platctl bootstrap --resume` picks up from the
  failed unit; it never re-runs completed ones.
- **Never run `platctl`/terragrunt from a git worktree** — a mismatched absolute path can flip a teardown
  provisioner and delete *live* IAM/ECR. Always operate from the main checkout.

## Go deeper

- [platctl & the deployment DAG](deep-dive-platctl-and-the-dag.md) — how the graph is discovered and walked,
  the full bootstrap ordering + the "why each before what," the hooks, teardown, and `validate`.
- [Parking & day-2 recovery](deep-dive-parking-and-day2.md) — the `down`/`up` choreography, the recovery
  sweeps, the gotchas, and every day-2 recovery story (meltdown → descheduler, and the rest).
- The lookup: the [Reference](reference.md). Related: [Foundations](../foundations/README.md),
  [Cost & FinOps](../cost/orientation.md) (parking is the biggest non-prod lever),
  [Secrets & config](../secrets-config/orientation.md) (the SOPS floor).
