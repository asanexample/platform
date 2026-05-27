# platctl Architecture

Internal design documentation for contributors.

## Package Structure

```text
internal/
├── engine/     Orchestration: DAG walker, parallel execution, state, logging
├── config/     Configuration: .platctl.yaml parsing, unit auto-discovery, hooks
├── cloud/      Provider abstraction: CloudClient interface, AWS implementation
└── cli/        Cobra commands: bootstrap, teardown, status, validate
```

**Dependency flow**: `cli` → `config` + `engine` + `cloud`. No circular imports. The `engine` package has no dependency on `config` or `cloud` — all configuration is injected via the `Unit` struct and interfaces.

## Auto-Discovery

platctl does not hardcode the dependency graph. Instead, it:

1. Reads `.platctl.yaml` for environment definitions (paths + providers)
2. Scans each environment's directory for subdirectories containing `terragrunt.hcl`
3. Parses each file using `hashicorp/hcl/v2` to extract `dependency` blocks
4. Resolves relative `config_path` values to qualified unit names (e.g., `"../networking"` → `platform/networking`, `"../../../../preprod/us-east-1/platform/eks"` → `preprod/eks`)
5. Merges `implicit_deps` from config overrides (for dependencies not expressed in terragrunt)
6. Constructs the complete DAG

**Key file**: `config/discover.go`

**Adding a new unit**: create the directory + `terragrunt.hcl`. No config changes needed.

**Adding a new environment**: add to `.platctl.yaml`, create the directory structure.

### Cross-environment dependency resolution

Same-env deps use simple relative paths (`../networking`). Cross-env deps use longer paths (`../../../../preprod/us-east-1/platform/eks`). The resolver:

1. Joins the config_path with the current unit's directory to get an absolute path
2. Matches the result against each environment's base path
3. Extracts the unit name from the remaining path suffix

## Engine Lifecycle

```text
Config → Discover → Graph → TopoSort → Parallel Walk → State Tracking → Summary
```

### DAG Walker (engine.go)

Uses Kahn's algorithm (in-degree counting) for topological execution:

1. Build in-degree map from the graph
2. Seed a ready set with zero-dependency units
3. Launch ready units as goroutines (bounded by concurrency semaphore)
4. When a unit completes, decrement dependents' in-degrees
5. Enqueue newly-ready units (in-degree reaches zero)
6. On failure: mark transitive dependents as skipped, wait for in-flight to finish

The `results` channel carries completions back to the main goroutine, which owns all state mutation (no concurrent map writes).

### Graph (graph.go)

Pure functions, no side effects:

- `NewGraph`: validates no duplicates, no missing deps
- `TopoSort`: deterministic topological ordering (sorted tie-breaking)
- `Waves`: groups units by parallel execution wave
- `Reverse`: flips edges for teardown
- `FilterByEnv`: removes cross-env edges for single-env runs
- `Dependents`: transitive closure for skip-on-failure

### Runner (runner.go)

Wraps `os/exec.Cmd` for terragrunt subprocess execution:

- `Binary` field controls the executable (defaults to `"terragrunt"`)
- Sets provider-specific env vars (`AWS_PROFILE`, `ARM_SUBSCRIPTION_ID`) based on `unit.Provider` and `unit.Auth`
- Captures stdout/stderr for logging
- `SCPProtectedTypes` field controls which resource types trigger SCP error detection (defaults to `aws_kms_key`, `aws_kms_alias`, `aws_flow_log`)
- Classifies errors by inspecting output:
  - SCP pattern → `SCPError` (engine can retry after `state rm`)
  - Lock pattern → `LockError` (prints force-unlock command)
  - Otherwise → `RunError`

### State (state.go)

JSON file (`.platctl-state.json`) tracking unit statuses:

- `pending` → `running` → `completed` | `failed`
- `skipped` (dependent of a failed unit)

`FileStore` uses a mutex for concurrent access and atomic writes (write to `.tmp`, rename). The main goroutine owns state transitions — goroutines send results via channel, never mutate state directly.

**Resume**: `PrepareForResume()` resets `failed` and `skipped` to `pending`, leaving `completed` intact.

## Hooks

Pre-apply operations defined in `.platctl.yaml` overrides:

### CRD Two-Stage (`crd_two_stage`)

Problem: Helm charts that define CRDs and custom resources in the same release fail on first install because CRDs don't exist when custom resources are planned.

Solution: Always run two stages regardless of CRD state:

1. `apply -target=<helm_release>` — installs the operator, registers CRDs
2. `apply` — full apply, custom resources can now reference CRDs

If CRDs already exist, stage 1 is a no-op. Idempotent.

### ENI IP Validation (`eni_ip_validation`)

Problem: cross-vpc-dns PHZ records reference EKS API ENI IPs in the terragrunt config. On cluster recreation, these IPs change.

Solution: query live ENI IPs via `aws ec2 describe-network-interfaces`, compare to the values in the terragrunt config, warn if stale.

### Secret Cleanup (`secret_cleanup`)

Problem: Secrets Manager secrets have a recovery window (default 30 days) after deletion. Teardown leaves secrets in "pending deletion" state, blocking recreation on the next bootstrap.

Solution: during teardown, force-delete specified secrets (no recovery window) so they can be cleanly recreated. Configured with a list of `profile:secret_id` pairs in `hook_config`.

## Cloud Abstraction

`cloud.Client` is the base interface (provider-agnostic operations like `SecretExists`). `cloud.AWSClient` extends it with AWS-specific operations. The `Registry` maps provider names to implementations.

Currently only AWS is implemented. Azure would add `cloud.AzureClient` and register it.

## Testing Strategy

All tests are in `_test.go` files alongside the code they test.

**engine package**: `graph_test.go` (topo sort, cycles, env filtering, full 33-unit graph), `engine_test.go` (parallel execution, failure/skip, resume, destroy reversal), `runner_test.go` (error classification, env var injection), `state_test.go` (transitions, concurrent writes, persistence)

**config package**: `discover_test.go` (fixture-based discovery, cross-env resolution, implicit deps, auth overrides), `hooks_test.go` (CRD two-stage call sequence, manual step checks with mock clients)

**All side effects behind interfaces**: the engine calls `Runner.Run()`, `Store.Save()`, and `cloud.Client` methods. Tests inject mocks that record calls and return canned responses. No real terragrunt, filesystem I/O (beyond temp dirs), or AWS API calls in unit tests.
