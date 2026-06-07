# Cost-Optimized Dev Profile — Rebuild Plan

**Status:** proposed (not yet implemented). **Goal:** rebuild platform + preprod in the *most cost-effective*
shape for a build/test/iterate environment, where **HA and AZ-resilience are explicitly not required**. Every
change is a **toggle** so we can flip back to a prod-grade posture later.

Context: the stack is fully torn down (see `platform-rebuild-from-scratch.md`). These changes land **before** the
next `platctl bootstrap`. Baseline today: **7 × t3.large on-demand ≈ $425/mo**.

---

## The five levers (decided)

| # | Lever | Decision |
|---|---|---|
| 1 | Single-AZ node placement | Yes (dev). Toggle to revert to 3-AZ. |
| 2 | Drop Mimir | Yes (toggle off). Prometheus local retention only. |
| 3 | Spot for workload tiers | Yes. System tiers stay on-demand. |
| 4 | Graviton (t4g) | Yes — all node groups. (ARM audit: green, below.) |
| 5 | Preprod minimal-always-on | Yes — 1 system + 1 spot workload. |

Why this is the right shape: observability is **already non-HA** — the 3-system-node floor comes from
single-replica StatefulSets with **AZ-pinned EBS volumes** spread across 3 AZs, plus a genuinely RAM-heavy stack.
So the wins are *collapsing the AZ spread* and *trimming the heaviest discretionary component (Mimir)* — not
"turning off HA."

---

## Part A — platform repo changes (this repo)

### A1. Single-AZ node placement (toggle)

- Add an env-level flag, default `true` for dev: `single_az_nodes` (in each env's `network.hcl`, exposed via
  `_base.hcl`).
- In both `node-groups` units, select **one** kubernetes subnet when the flag is set, all three otherwise — and
  pin **system + workload to the same AZ** so they co-locate with their volumes:

  ```hcl
  locals {
    k8s_subnets = [for name, id in dependency.networking.outputs.subnet_ids : id if can(regex("kubernetes$", name))]
    az_subnets  = include.base.locals.single_az_nodes ? slice(sort(local.k8s_subnets), 0, 1) : sort(local.k8s_subnets)
  }
  # each node group: subnet_ids = local.az_subnets
  ```

- No StorageClass change needed: `gp3` is already `WaitForFirstConsumer`, so EBS volumes bind in the AZ the pod
  lands in. With single-AZ nodes, every pod + volume lands in the one AZ.
- **Trade-off:** zero AZ resilience (one AZ outage = cluster down) — acceptable for build/test. Flip
  `single_az_nodes = false` to restore 3-AZ spread.

### A2. Graviton (t4g) — all node groups

- Per node group: `instance_types = ["t4g.large"]`, `ami_type = "AL2023_ARM_64_STANDARD"`.
- Drive these from a small `node_arch` local (`"arm64"` dev / `"amd64"` revert) so the switch is one value.
- Same 2 vCPU / 8 GiB as t3.large, ~20% cheaper (~$49 vs ~$61/mo), better price/perf.
- **Gated on Part B** (multi-arch images). ARM audit below: all platform images are arm64-ready.

### A3. Spot — workload tiers only

- `workload` node groups (both envs): `capacity_type = "SPOT"`, and diversify the pool for availability:
  `instance_types = ["t4g.large", "t4g.xlarge", "m6g.large", "m7g.large"]` (all Graviton).
- `system` tiers stay `ON_DEMAND` (they run Cilium/CoreDNS/Keycloak/CNPG/observability — disruption-sensitive +
  stateful). Workload runs only stateless ArgoCD-managed app pods → ArgoCD reschedules on interruption.

### A4. Right-size counts

| Env | Group | Today | Dev profile | Notes |
|---|---|---|---|---|
| platform | system | 3 (min 3) | **2** (min 2, max 3) | Mimir gone + single-AZ removes the 3-AZ floor; RAM-bound. **Validate fit; bump to 3 if pods pend.** |
| platform | workload | 1 | 1 (spot, max 6) | |
| preprod | system | 2 (min 2) | **1** (min 1, max 2) | Lighter (no observability/keycloak/backstage). **Crossplane tenant control plane + Falco are RAM-heavy — bump to 2 if tight.** |
| preprod | workload | 1 | 1 (spot, max 6) | |

No cluster-autoscaler exists, so `desired == min` is always-on. (Karpenter would let these scale to zero — noted
as a future lever, out of scope here.)

### A5. Disable Mimir + lighten observability (toggle)

- Add `enable_mimir` flag, default `false` for dev.
- `mimir` unit: `create = include.base.locals.enable_mimir` → applies as a no-op (empty state) when off.
- `observability` unit: `mimir_remote_write_url = enable_mimir ? "http://mimir-gateway..." : ""` (already
  conditional in the module).
- **Optional further saving (recommended for dev):** `observability` `use_persistent_storage = false` →
  Prometheus/Alertmanager run on `emptyDir` (ephemeral metrics, lost on pod restart — fine for dev). Removes the
  last 2 AZ-pinned observability volumes + ~25 GiB EBS. Keep CNPG (Keycloak/Backstage DBs) persistent.
- Net: Prometheus-only metrics with short local retention; ~8 fewer pods, 3 fewer EBS volumes, one fewer S3
  bucket. `create_default_storageclass` stays **on** (CNPG still needs gp3).

---

## Part B — cross-repo ARM/multi-arch CI (app repos)

The platform layer needs **zero** image work (audit below). Only **our** images need multi-arch builds. All base
images are already multi-arch; the work is CI config. I have write access to all four repos.

### B1. `asanexample/trusted-ci` — `build-sign.yml` (covers ALL tenant apps at once)

- It already has a `platforms` input wired to `docker/build-push-action@v6` — it's half-done. Add
  `docker/setup-qemu-action@v3` and default `platforms` to `linux/amd64,linux/arm64`.
- One change → app-alpha, app-bravo, and every future tenant app build multi-arch.

### B2. `asanexample/app-alpha` + `asanexample/app-bravo`

- Pass `platforms` in the `deploy.yml`/`preview.yml` calls (or inherit the new default).
- Add the Go cross-compile pattern to the Dockerfile so builds are **native-speed, no QEMU**:

  ```dockerfile
  FROM --platform=$BUILDPLATFORM golang:1.24-alpine AS build
  ARG TARGETOS TARGETARCH
  RUN GOOS=$TARGETOS GOARCH=$TARGETARCH go build -o /app ...
  # runtime stays: FROM gcr.io/distroless/static-debian12:nonroot  (already multi-arch)
  ```

  (bravo is the generic starter → effectively one change cloned to alpha.)

### B3. `asanexample/backstage` — its own `build.yml` (Node, not trusted-ci)

- Node + yarn build is slow under QEMU emulation → build on a **native arm64 runner**
  (`runs-on: ubuntu-24.04-arm`) and set `platforms: linux/arm64` (or multi-arch with a matrix).
- Re-push the image to the recreated `platform/backstage` ECR repo (multi-arch) before the `backstage` wave.

### Supply chain: unaffected

Cosign signs the multi-arch **index** digest; Kyverno `verifyImages` and the SLSA provenance validate the index
as-is. No policy or signing changes.

---

## ARM compatibility audit (results)

**Third-party images: 100% arm64-ready** — verified via `docker buildx imagetools inspect`:

- ArgoCD, Keycloak, Dex, oauth2-proxy ✅
- CNPG + the Postgres image (Keycloak/Backstage DBs) ✅
- Crossplane core, the Upbound `provider-aws` family (family/ecr/iam/eks), all 3 Composition functions ✅ *(the
  biggest unknown — clean)*
- Cilium, Kyverno, cert-manager, external-dns, external-secrets, Tailscale, Falco, the full Prometheus stack
  (operator/grafana/KSM/node-exporter), CoreDNS, kubectl ✅

**Custom images: no blockers** — base images already multi-arch (`golang:1.24-alpine`,
`distroless/static-debian12`, Node 24); the only work is enabling multi-arch in the 3 pipelines above.

Definitive proof is the rebuild itself — any arm64 gap surfaces immediately as `ImagePullBackOff`.

---

## Part C — platctl env-lifecycle commands (park / teardown an environment)

Operational tooling for the "park when idle" cost model. preprod stays **minimal-always-on** by default; these
let you drop it (or platform) further when idle.

- **Per-env teardown — already exists:** `platctl teardown --env <env>` (the `--env` filter + `FilterByEnv`).
  Caveat to document: while preprod is gone, platform's `argocd-clusters` (registers preprod) and Backstage's
  preprod K8s view show transient "cluster unreachable" errors — cosmetic; they reconnect on rebuild.
- **New: `platctl down --env <env>` / `platctl up --env <env>`** (Go, `cmd/platctl/`):
  - `down` → set every managed node group in the env's cluster to `desiredSize=0, minSize=0` via the EKS
    `UpdateNodegroupConfig` API (seconds; nodes drain over a few min). **Non-destructive** — keeps the EKS control
    plane and all EBS volumes, so CNPG (Keycloak/Backstage) data survives and pods just reschedule on `up`.
  - `up` → re-apply the env's `node-groups` unit (terragrunt) to restore the configured sizes. The HCL stays the
    single source of truth; the API-induced drift self-heals on any normal apply.
  - Cluster name per env: add an optional `cluster` to `EnvConfig` (default `<env>-use1-eks`); node-group names
    via `ListNodegroups`; AWS profile from the env/iam-roles auth.
  - Generalizes to `prod` for free (env model already supports it).

**Cost spectrum by idle duration** (per env):

| State | Mechanism | ~Cost (preprod) | Resume |
|---|---|---|---|
| Active testing | minimal-always-on (1+1) | ~$64/mo nodes + $105 cluster/NAT | — |
| Overnight / daily cycle | `platctl down --env preprod` | ~$105/mo (control plane + NAT; nodes off) | ~5 min, data intact |
| Idle days+ | `platctl teardown --env preprod` | ~$0 | ~40 min (reliable rebuild) |

`platctl down/up` works for **platform** too (parks ArgoCD/Keycloak/Backstage; CNPG EBS data persists) — for
nights/weekends when nobody's using the IDP.

## Deferred — Karpenter (future lever, NOT now)

Karpenter scales nodes to pod demand; it does **not** make an always-on control plane cheap to park, so it does
**not** help the "park preprod when idle" goal (the always-on system stack + the CNI/Karpenter landing node floor
preprod at ~1 node + the $73/mo control plane — same as minimal; only teardown reaches ~$0). The big cost wins are
already captured by this profile (~58%). Karpenter's payoff is the **bursty workload tier** — tenant app pods and
**PR preview environments** — once those are actually running. Introduce it then, **scoped to the platform
`workload` tier** (keep a small managed `system` node group for Cilium/CoreDNS/Karpenter + the control plane);
it replaces the fixed `workload` group, never `system`. Adding it during this rebuild (also the first real apply
of the identity stack) is too many new variables at once.

## Sequencing

1. **This repo (Part A)** — make the dev-profile config changes; PR + merge.
2. **App repos (Part B)** — multi-arch CI: `trusted-ci` first, then app-alpha/bravo, then backstage; merge.
3. **Bootstrap** — `platctl bootstrap`. Early waves recreate ECR (incl. `platform/backstage`). **Trigger the
   Backstage `build.yml`** once that repo exists → multi-arch image lands before wave 9. Tenant app images
   (alpha/bravo) build multi-arch when you onboard/test tenants (later, GitOps via ArgoCD).
4. **Validate + measure** — confirm pods schedule on the reduced counts; use the (now-deployed) Prometheus to
   check actual utilization; bump `platform/system` → 3 or `preprod/system` → 2 only if there's scheduling
   pressure.

---

## Cost estimate

| | Today | Dev profile |
|---|---|---|
| platform nodes | 4 × t3.large = ~$243 | 2 × t4g.large system + 1 × t4g spot ≈ **~$113** |
| preprod nodes | 3 × t3.large = ~$182 | 1 × t4g.large system + 1 × t4g spot ≈ **~$64** |
| **Node total** | **~$425/mo** | **~$177/mo (~58% off)** |
| EBS | Mimir 40Gi + Prom/AM 25Gi + DBs | −Mimir, −Prom/AM (if ephemeral) → DBs only |
| Data transfer | cross-AZ | single-AZ (lower) |

Further: **preprod scaled-to-zero when not tenant-testing** → another ~$64/mo. Graviton already baked into the
above (~20% vs on-demand t3).

---

## Revert to prod-grade (the toggles)

| Flag | Dev | Prod |
|---|---|---|
| `single_az_nodes` | `true` | `false` (3-AZ) |
| `node_arch` | `arm64` (t4g) | `amd64` (t3) or keep t4g |
| workload `capacity_type` | `SPOT` | `ON_DEMAND` |
| platform/preprod system counts | 2 / 1 | 3 / 2 |
| `enable_mimir` | `false` | `true` |
| observability `use_persistent_storage` | `false` | `true` |
| per-module `high_availability` | `false` | `true` |

(These could later be unified under a single `environment_class = dev|prod` profile; for now they're discrete,
well-named flags.)

---

## Risks & mitigations

- **Spot interruption** — workload tier only (stateless ArgoCD apps); ArgoCD reschedules. Diversified instance
  pool for availability. Low risk.
- **Single-AZ outage** — takes the cluster down; dev-acceptable, one-flag revert.
- **2-node platform-system fit** — heavy stack on 2 × t4g.large (16 GiB) may be tight; max=3 headroom + measure,
  bump if pods pend. (Mimir-off + ephemeral-Prometheus frees the most room.)
- **preprod 1-node fit** — Crossplane control plane + Falco are RAM-heavy; bump to 2 if tight.
- **Backstage QEMU build time** — use a native arm64 runner.
- **Spot capacity in a single AZ** — diversified instance types; worst case pods pend (dev-acceptable).
