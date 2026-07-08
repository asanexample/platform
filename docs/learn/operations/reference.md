# Learn: Operations — reference

Look-up, not a lesson. Build the model in the [orientation](orientation.md) first. Verified against code
(`cmd/platctl/`, `.platctl.yaml`), the runbooks/skills, and live (both clusters up). No account IDs or emails
appear here (`.platctl.yaml` + ADR-006 contain real ones — omitted; VPC CIDRs `10.100/10.101` are RFC-1918,
non-sensitive).

## platctl — the DAG orchestrator

- **What:** a DAG-aware Go/Cobra CLI (`cmd/platctl/`) that discovers and walks the ~98-unit graph it finds
  (65 platform + 33 preprod; the ~110 units on disk include the mgmt-account floor it never touches), in
  dependency order, parallel where safe. Build: `make build-platctl` → `./bin/platctl <cmd>` (**not on PATH**).
- **Verbs:** `bootstrap` (walk forward), `teardown` (reverse), `down`/`up` (park), `validate` (health),
  plus `kubeconfig`, `status`, `access` (ADR-088 workforce). All built + tested (unit tests per package).
- **DAG is discovered, not hardcoded** (`config/discover.go`): read `.platctl.yaml` env defs → scan for
  `terragrunt.hcl` → parse each unit's `dependency` blocks (hashicorp/hcl) → resolve relative `config_path`
  to qualified unit names (incl. cross-env edges, e.g. platform ArgoCD → preprod EKS) → merge `implicit_deps`
  overrides → build the graph. Add a unit = drop a `terragrunt.hcl`; no platctl change.
- **Walk** (`engine/graph.go`, `engine.go`): Kahn's algorithm (in-degree), goroutines bounded by a semaphore
  (default 4 apply / 8 validate); a single goroutine owns all state. `TopoSort` / `Waves` (what `--dry-run`
  prints) / `Reverse` (teardown) / `FilterByEnv` (`--env`) / `Dependents` (skip-on-failure).
- **Resume:** `.platctl-state.json` (`pending→running→completed|failed|skipped`); on failure marks the unit +
  dependents `skipped`, lets in-flight finish, prints `--resume`. Logs → `.platctl-logs/latest/<wave>_<unit>.log`.

## Bootstrap ordering (the "why")

- **The floor (below platctl, ADR-002/006):** `state-bootstrap` uses a *local* backend on first apply (can't
  store state in the bucket it's creating), makes the S3 bucket + DynamoDB lock table (migrating its *own* state to S3 is a tracked follow-up — stays local).
  Lives under `mgmt/global/` outside the env trees → platctl never discovers/touches it. Escapes:
  `TG_SOPS_BOOTSTRAP=1` (plaintext `secrets.hcl` before the KMS key exists), `TG_FORCE_DEPLOYER=1` (CI runner).
- **Cluster spine (ADR-008/009):** `iam-roles`+`networking` → `eks` → `cilium` → `node-groups` →
  `eks-addons` (+`karpenter`). Cilium is BYOCNI and must run before nodes join (no-CNI node = `NotReady`);
  CoreDNS can't schedule until CNI+nodes ready — so EKS is split into separate units, ordering is
  structural, not `depends_on`.
- **Bootstrap-then-lockdown (ADR-010):** EKS API is private-only by default; bootstrap applies it with
  `endpoint_public_access=true` (no in-VPC path yet), then a lockdown phase re-applies *in order*:
  (1) Tailscale split-DNS on → (2) EKS public endpoint off → (3) refresh `cross-vpc-dns` PHZ (endpoint churn
  rotates the API ENIs). `applyLockdownWithRetry` 8×45s on transient EKS updates. platctl owns the toggle.
- **Platform services:** `external-secrets`→`secret-stores` before ExternalSecret consumers; `keycloak`→
  `keycloak-config`→`argocd`/Grafana OIDC (OIDC direct to Keycloak, Dex retired ADR-053/059); `policy` before
  `crossplane`; `gateway` early.
- **Pre-flight:** `manual_steps` (`.platctl.yaml`) — e.g. Cloudflare token, Tailscale key — with a `check`
  (auto-skip if satisfied; `--yes` skips prompts). Hooks (`hooks/hooks.go`): `crd_two_stage` (register
  CRDs then apply CRs), `eni_ip_validation`, `argocd_account_token` (re-mint Backstage's token post-rebuild),
  `secret_cleanup` (pre-apply: dodge the SM 30-day recovery window).

## Teardown

- **Unlock phase first:** walk lockdown in reverse — re-enable the public EKS endpoint (Tailscale is about
  to be destroyed, so it's the only way to reach the API to delete K8s resources).
- **Reverse-DAG destroy** (`graph.Reverse()`): dependents before dependencies; `mock_outputs` (incl. `destroy`)
  let reverse-destroy plan even with upstream state gone. `teardown_args` add force-destroy vars (ECR/S3).
- **Floor exclusion:** `teardown_skip: true` marks `iam-roles` `completed` up front (destroying PlatformDeployer
  would force the next bootstrap through break-glass); the mgmt floor is outside the discovered trees;
  `sops-kms` has `prevent_destroy`.
- **⚠️ Never apply/teardown from a git worktree:** abs-path `null_resource` triggers used to fire `when=destroy`
  provisioners that force-deleted **live** IAM/ECR. Fixed (path via `git rev-parse` now), but the rule stays —
  operate from the main checkout.

## Validate

Two-phase (`validate/**`, concurrency 8): **Phase 1 IAM** (SSO valid, deployer assumable, state access) —
if it fails, Phase 2 is skipped (avoid a cascade of misleading errors). **Phase 2** per-unit checkers by
convention (`eks`→cluster ACTIVE+nodes Ready; `cilium`→agent workload; `argocd`→Apps Synced+Healthy; generic
`StateCheck` otherwise) + cross-cutting (`GatewayHealthCheck`, `TailscaleCheck`, `DNSDelegationCheck`,
`EndpointCheck` HTTP 200/302). Flags: `--env`, `--check <prefix>` (`--check tailscale` = ~ms probe),
`--concurrency`.

## Parking — `platctl down`/`up` (LIVE both clusters)

- **Idea:** scale EKS node groups to `desiredSize=0` overnight → ~all compute cost gone. Non-destructive:
  the control plane + every EBS volume (CNPG DBs) survive. ≠ teardown. Biggest non-prod cost lever.
- **DOWN** (`scale.go`): 0. credential preflight (fail-fast — a swallowed `ExpiredToken` once half-parked and
  reported success). 1. clear `karpenter.sh/do-not-disrupt` (else the drain hangs). 2. delete NodePool and
  EC2NodeClass symmetrically, poll NodeClaims gone (cascade returns early). 3. scale node groups → 0 (drain
  respects PDBs, force-terminate stragglers after ~2 min). 4. stop the SSM bastion. Cost-zero = system group
  0 + zero instances + bastions stopped.
- **UP:** credential preflight (both profiles) → re-apply `node-groups` → start bastion → wait for cluster
  API before Karpenter (early apply orphans its Helm releases, #660) → recreate NodePool+EC2NodeClass
  (`-replace`) → `assertKarpenterReady` (self-heals) → `recoverKyverno` → `runReconnect` → `recoverStartupOrderedDBClients`.
- **Gotchas:** (1) kubectl unreachable after park (TS router gone) → verify via `aws eks describe-nodegroup`.
  (2) unpark = fresh admission of every pod → exposes latent policy/IAM bugs (a masked account-less ECR ARN
  once denied all workloads); restarting Kyverno won't fix an IAM gap. (3) judge by pod readiness, not node
  state (a client up before its DB, never retries).
- **Living doc:** the `cluster-parking` skill is "not yet stable" — read the Learnings log before, append after,
  every park/unpark.

## Rebuild — `teardown` → `bootstrap` (validated offline)

- **Thesis:** git IS the platform (IaC + GitOps + committed SOPS) → destroy + rebuild from zero. Runbook: *"data
  loss is expected; success = fully reconstructable from code."* Dogfooded: repeated clean bootstrap +
  teardown cycles (fixes merged #241/#292). Payoffs: DR, drift-elimination, no-snowflake-proof, confidence.
- **Seed-vault floor (must survive):** S3 state backend (holds the state the rebuild reads) + `platform-sops`
  KMS key (decrypts committed config). Protected: outside platctl's teardown scope + `prevent_destroy`.

## Day-2 recovery (each: failure → durable fix)

- **Node-imbalance meltdown → descheduler** ([ADR-093](../../adrs/093-descheduler-node-rebalancing.md)): post-
  unpark one node hit 59 pods/~99% CPU, kubelet degraded, Karpenter crash-looped → deadlock. Band-aid: delete
  the Karpenter pod. Durable: descheduler `LowNodeUtilization` (PDB-safe, `nodeFit`), live both clusters
  (platform `*/15` 40/70; preprod `*/10` 50%). *(Doc-drift: ADR-093 header still says `Proposed` — it's
  live+proven; flag to flip.)*
- **DB-client startup-ordering → `platctl up` DB-recovery** (#1105, hardened #1183): a client up before its
  CNPG DB never retries → restart exactly those (bounded ~12 min; #1183 fixed a silent no-op on cold unpark).
- **Stale cross-VPC DNS → `platctl up` reconnect** (#540): preprod ENIs rotate → ArgoCD dials dead IPs →
  re-apply `cross-vpc-dns` + restart the controller.
- **Kyverno helm orphaned from TF state → import + apply** (`terragrunt import 'helm_release.kyverno[0]'…`;
  teardown-scoped, not unpark).
- **Helm stuck `pending-upgrade` → delete the pending revision secret** (`sh.helm.release.v1.<rel>.v<N>`) +
  re-apply; durable lesson = run slow applies in the background.
- **Discipline** (`feedback_durable_fix_over_hotfix`): on any failure, fix the *source* + commit + PR (manual
  unblock OK, but land the durable fix). The tell it's real: #1183 fixed a bug *in a previous durable fix*.

## Status ledger

- **Live + proven:** platctl (all verbs, tested); parking both clusters; descheduler both clusters; the `up`
  DB-client + DNS recovery sweeps.
- **Validated (offline):** teardown/rebuild reconstructability (repeated clean cycles, zero manual steps).
- **Maturing / rebuild-gated:** park/unpark "not yet stable" (living doc); Keycloak + v3 cutovers verified only
  offline (next rebuild = first live apply); ADR-006 migrate-bootstrap-state-to-S3 follow-up (bootstrap's own
  state still local).

## Gotchas (quick)

- **`platctl` isn't on PATH** — `make build-platctl` → `./bin/platctl`.
- **Never operate from a worktree** — main checkout only.
- **Confirm a park via the EKS API**, not kubectl.
- **Unpark exposes latent bugs** — a green cluster can still be broken; judge by pod readiness.
- **`--resume`** after a mid-bootstrap failure; never re-runs completed units.

## Go deeper

Deep dives: [platctl & the DAG](deep-dive-platctl-and-the-dag.md) ·
[parking & day-2 recovery](deep-dive-parking-and-day2.md). Skills: `platctl`, `apply-and-destroy`,
`cluster-parking`. Runbooks: `docs/runbooks/platform-rebuild-from-scratch.md`,
`docs/runbooks/cluster-scale-down-up.md`. ADRs:
[006](../../adrs/006-state-bootstrap-pattern.md) · [008](../../adrs/008-cilium-as-cross-cloud-cni.md) ·
[009](../../adrs/009-eks-component-separation.md) · [010](../../adrs/010-private-eks-api-endpoint.md) ·
[093](../../adrs/093-descheduler-node-rebalancing.md). Related: [Foundations](../foundations/README.md),
[Cost & FinOps](../cost/orientation.md).
