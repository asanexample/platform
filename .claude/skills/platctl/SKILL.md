---
name: platctl
description: >-
  How to use platctl, the repo's DAG-aware Go orchestrator for platform infrastructure
  (cmd/platctl). Use when bootstrapping or tearing down the platform from scratch, parking
  or restoring a cluster overnight (down/up), running post-apply health checks (validate),
  configuring kubeconfig, or editing .platctl.yaml. It covers the build step (it's NOT on
  PATH), the command/flag tree, and the gotchas — resume, the EKS public-endpoint
  unlock/lockdown automation, and the Karpenter-drain ordering on park. Prefer platctl over
  raw `terragrunt run --all` for full bootstrap/teardown. NOT for single-unit
  apply/edit (use the terragrunt-units / apply-and-destroy skills).
---

# platctl — platform orchestrator

`platctl` is the DAG-aware Go CLI (`cmd/platctl/`) that drives full-platform bootstrap,
teardown, parking, validation, and kubeconfig. It's smarter than raw `terragrunt run --all`:
parallel waves in dependency order, resumable state, manual-prereq checks, per-unit hooks,
and the EKS public-endpoint unlock/lockdown dance. Source of truth: `cmd/platctl/README.md`,
the cobra commands under `cmd/platctl/internal/cli/`, and `.platctl.yaml`.

## Build & invoke — it is NOT on PATH

```bash
make build-platctl     # → ./bin/platctl  (cd cmd/platctl && go build -o ../../bin/platctl)
./bin/platctl <cmd>    # always the relative path, or build first; bare `platctl` fails
```

## Commands

| Command | What it does | Key flags |
|---|---|---|
| `bootstrap` | Deploy all units in DAG order (parallel waves), then the lockdown phase (e.g. disable public EKS endpoint), then kubeconfig | `--env`, `--dry-run`, `--resume`, `--yes`, `--concurrency` (4) |
| `teardown` | Unlock phase (re-enable access) → pre-destroy `teardown_args` → destroy in reverse DAG | `--env`, `--dry-run`, `--resume`, `--yes`, `--concurrency` |
| `validate` | Two-phase health checks: Phase 1 IAM (gates Phase 2), Phase 2 per-unit + cross-cutting (gateway, DNS, Tailscale, endpoints) | `--env`, `--check <prefixes>` (e.g. `tailscale,gateway`), `--concurrency` (8) |
| `kubeconfig` | `aws eks update-kubeconfig` for each cluster in `.platctl.yaml` `kubeconfig:` | `--env` |
| `status` | Read `.platctl-state.json`, show per-unit state | `--watch`/`-w`, `--interval` (5) |
| `down` | **Park** an env: drain Karpenter → delete NodePool → scale managed groups to 0/0 → force-terminate stuck nodes. Control plane + EBS survive | `--env` (required), `--yes` |
| `up` | **Restore** a parked env: re-apply node-groups → wait for cluster API (~15m) → re-apply karpenter → best-effort Kyverno recovery → reconnect steps | `--env` (required) |

```bash
./bin/platctl bootstrap --dry-run        # preview the plan
./bin/platctl bootstrap                  # full from-scratch
./bin/platctl bootstrap --env platform   # one environment
./bin/platctl bootstrap --resume         # continue after a failure
./bin/platctl validate --check tailscale
./bin/platctl down --env platform        # park overnight
./bin/platctl up   --env platform        # restore
```

## Gotchas worth knowing

- **`--resume`:** on failure, platctl marks the failed unit + its dependents skipped, finishes
  in-flight units, and saves `.platctl-state.json`. A fresh run detects stale state and prompts
  to resume or start over. `--resume` skips completed units.
- **EKS public-endpoint unlock/lockdown is automatic.** `bootstrap` keeps the endpoint open
  (`bootstrap_args`) for API reachability during apply, then the **lockdown** phase re-applies
  to disable it (retries up to ~6 min — the EKS update races other cluster updates). `teardown`
  runs an **unlock** phase first to re-enable it so destroy can reach the API. Don't toggle the
  endpoint by hand — see the cluster-access skill for the never-enable-public norm.
- **Park drains Karpenter FIRST** (`down`): clearing the NodePool before scaling managed groups,
  so the system group dying mid-park doesn't orphan Karpenter-provisioned EC2 (ADR-078). `up`
  waits for the cluster API before re-applying karpenter (applying early orphans its helm
  releases) and best-effort restarts Kyverno (sigstore TUF cache can fail-close all policed pods).
- **Logs**: full terragrunt output per unit under `.platctl-logs/latest/<wave>_<unit>.log`
  (`latest` is a symlink to the timestamped run dir; `/` in unit names becomes `--`, e.g.
  `001_platform--eks.log`).

## `.platctl.yaml`

Repo-root config: `environments` (path/provider/auth + `reconnect`), per-unit `overrides`
(`bootstrap_args`/`teardown_args`, `hook`, `implicit_deps`, `teardown_skip`), `manual_steps`
(prereq checks), `lockdown` steps, `kubeconfig` entries, and `validate` checks. Edit it to wire
a new unit's teardown args, a hook, or a manual prerequisite.

## References

- `cmd/platctl/README.md` — the authoritative command + config reference
- `cmd/platctl/internal/cli/` — cobra command definitions (real flags)
- `docs/runbooks/platform-rebuild-from-scratch.md` — the end-to-end from-scratch procedure platctl drives
- Related skills: **apply-and-destroy** (raw terragrunt + ordering), **cluster-access** (kubeconfig / Tailscale)
