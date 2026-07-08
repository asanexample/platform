# Learn: Operations

How the platform gets *run* — stood up, parked overnight for cost, rebuilt from zero, and recovered the
morning it breaks. The tool for all of it is `platctl`, a DAG-aware orchestrator that walks the ~98-unit
dependency graph so no human has to remember the order.

This is for platform engineers who operate the stack. [Foundations](../foundations/README.md) covers what the
pieces are, and reading it first helps, but you can follow along here with Terragrunt and a working sense of
"control plane vs worker nodes."

## Read in this order

1. **[Orientation](orientation.md)** — the platform is a dependency graph you can replay. `platctl` as a build
   system for the platform; the four verbs (build → park → rebuild → recover); the git-repo-*is*-the-platform
   thesis; operate-by-durable-fix. Metaphors: a build system, a phoenix, a seed vault.
2. **[Reference](reference.md)** — the dense lookup: platctl and the discovered DAG, the bootstrap ordering,
   teardown, validate, parking, rebuild, the day-2 recovery stories, the status ledger, gotchas.

## Go deep

- **[platctl & the deployment DAG](deep-dive-platctl-and-the-dag.md)** — how the graph is *discovered*
  (dependency-block parsing + Kahn's-algorithm parallel walk), the full bootstrap ordering and why each unit
  comes before what (the state-backend floor, Cilium-first BYOCNI, bootstrap-then-lockdown), the hooks,
  teardown and the worktree rule, and two-phase `validate`.
- **[Parking & day-2 recovery](deep-dive-parking-and-day2.md)** — the `down`/`up` choreography (non-destructive
  scale-to-zero, the ordering scars), the `up` recovery sweeps, the three counter-intuitive gotchas, and every
  day-2 recovery story (the node-imbalance meltdown → descheduler, DB-client ordering, DNS reconnect, and more),
  under the durable-fix discipline.

## Then

- What the pieces are: [Foundations](../foundations/README.md). Why parking matters:
  [Cost & FinOps](../cost/orientation.md) (the biggest non-prod lever). The committed-config floor:
  [Secrets & config](../secrets-config/orientation.md). Runbooks:
  `docs/runbooks/platform-rebuild-from-scratch.md`, `docs/runbooks/cluster-scale-down-up.md`.
