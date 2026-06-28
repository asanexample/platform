# ADR-038: platctl CLI for Platform Operations

**Date:** 2026-05-28

**Status:** Accepted

## Context

Deploying the platform requires running Terragrunt commands in the correct order across
multiple AWS accounts and environments. The dependency DAG spans 25+ units with specific
`AWS_PROFILE` requirements, cross-account role assumptions, and pre/post-deployment hooks.
Raw Terragrunt commands are error-prone: wrong execution order, wrong profile, missed
dependencies, and forgotten lockdown steps all cause partial deploys that are difficult to
recover from.

The platform stack has ordering constraints that `terragrunt run --all` cannot express:

- **Bootstrap overrides.** EKS must be initially deployed with `endpoint_public_access=true`
  so Terragrunt can reach the API, then locked down to private-only after the VPN (Tailscale)
  is operational. This requires an apply-with-args followed by a re-apply-without-args sequence
  that Terragrunt has no native mechanism for.

- **CRD chicken-and-egg.** Modules like Tailscale Operator define custom resources that
  reference CRDs registered by the operator itself. A two-stage apply (operator first, then
  full apply) is needed, but Terragrunt targets this at the Helm release level, not the module
  level.

- **Secret lifecycle.** Secrets Manager secrets pending deletion from a previous teardown block
  re-creation. Cleanup must run before apply, requiring a pre-hook that queries the AWS API.

- **Cross-account ordering.** The preprod `iam-roles` unit must be applied with a direct SSO
  profile (`preprod`), while all other preprod units use the management profile to assume
  `PlatformDeployer`. This per-unit auth override is invisible to `terragrunt run --all`.

- **Implicit dependencies.** Some units depend on resources in other environments (e.g.,
  `tailscale-admin` in platform depends on `iam-roles` in preprod). These cross-environment
  edges are not captured in Terragrunt `dependency` blocks.

- **Resumability.** A 25-unit deploy takes 30+ minutes. If unit 18 fails, re-running from
  scratch wastes time re-applying completed units. The operator needs a `--resume` flag that
  skips completed work.

### Alternatives Considered

**1. Shell scripts.** The original approach (`scripts/bootstrap-platform.sh`). Simple to write
but brittle: hardcoded unit ordering, no parallelism, no resume support, no pre-flight
validation. Adding a new unit requires editing the script in multiple places (deploy order,
destroy order, profile mapping). Error handling is limited to `set -e`, which aborts on the
first failure with no indication of which downstream units are affected.

**2. Makefile.** Better than scripts for expressing dependencies between targets, but still
imperative. Make's DAG is target-based (files on disk), not unit-based, so modeling Terragrunt
units requires synthetic phony targets. Parallel execution (`make -j`) works but has no
awareness of cross-account auth, no built-in state tracking for resume, and no hook system.
The Makefile would need shell scripts for hooks anyway, eliminating the simplicity advantage.

**3. Taskfile (go-task/task).** YAML-based task runner with dependency ordering and
parallelism. Closer to the right abstraction but still requires manual dependency declaration
(duplicating what Terragrunt already knows). No auto-discovery of units from `terragrunt.hcl`
files. Hooks, state tracking, and validation would need to be implemented as shell commands
embedded in YAML, limiting type safety and testability.

**4. Custom Go CLI (chosen).** A purpose-built CLI (`cmd/platctl/`) using Cobra for command
structure and a DAG engine for execution. Auto-discovers units by scanning `terragrunt.hcl`
files and parsing their `dependency` blocks with the HCL library. Supports typed hooks,
resumable state, parallel execution with configurable concurrency, and a post-deploy
validation framework. The same language as Terratest, so the team already has Go expertise.

## Decision

Build a Go CLI (`cmd/platctl/`) with seven subcommands (the five below, plus `down`/`up` for overnight
cluster parking — scale the managed node groups to zero and restore them, ADR-078):

### `platctl bootstrap`

Deploys all Terragrunt units in topological order. Auto-discovers units from `terragrunt.hcl`
files, parses `dependency` blocks to build the DAG, and executes independent units in parallel
(default concurrency: 4). Supports:

- `--env <name>` to target a single environment (e.g., `--env platform`)
- `--dry-run` to preview the execution plan as numbered waves
- `--resume` to continue from a previous incomplete run (skips completed units)
- `--yes` to skip interactive prompts (for CI)
- `--concurrency <n>` to control parallelism

After all units complete, a lockdown phase re-applies units that had bootstrap overrides
(e.g., EKS) without those overrides, hardening the configuration. Kubeconfig contexts are
configured automatically at the end.

### `platctl teardown`

Destroys all units in reverse topological order. Before destroying, runs an unlock phase that
re-applies bootstrap overrides (e.g., re-enabling public EKS endpoint) so Terragrunt can
reach the API during destroy. Pre-destroy applies handle Terraform state attributes that must
be updated before destruction (e.g., `force_destroy=true` on S3 buckets). Units with empty
state are detected in parallel and skipped automatically.

### `platctl validate`

Runs health checks against deployed infrastructure in two phases:

- **Phase 1 (IAM):** SSO session validity, cross-account role assumptions, kubeconfig role
  access, and S3 state backend connectivity. If Phase 1 fails, Phase 2 is skipped to avoid
  cascading errors from expired credentials.
- **Phase 2 (infrastructure):** Per-unit checks (Terraform state, EKS cluster status, node
  readiness, pod health, SecretStore status, ArgoCD app sync) and cross-cutting checks
  (Gateway health, DNS delegation, Tailscale subnet routing, HTTP endpoint reachability).

Supports `--check <prefix>` to run a subset of checks and `--env` to scope to one
environment.

### `platctl kubeconfig`

Configures kubectl contexts for all clusters defined in `.platctl.yaml` using
`aws eks update-kubeconfig` with the appropriate admin role and profile. Supports `--env`
filtering.

### `platctl status`

Displays the state of the last bootstrap or teardown operation from the persisted
`.platctl-state.json` file, showing per-unit status (completed, failed, skipped, pending)
with durations.

### `platctl down` / `platctl up`

Park / unpark an environment overnight (ADR-078): `down` scales the managed node groups to zero
(non-destructive — control plane + EBS/CNPG data preserved, Karpenter drained first), `up` restores
them. See the `cluster-parking` skill.

### Architecture

The CLI's internal packages include:

- **`config`** — Parses `.platctl.yaml` (environments, per-unit overrides, manual steps,
  lockdown steps, kubeconfig entries, validation config). Auto-discovers units by walking
  environment directories and parsing `terragrunt.hcl` dependency blocks with the
  `hashicorp/hcl/v2` library. Implements hooks: `CRDTwoStageHook` (two-pass apply for CRD
  registration), `SecretCleanupHook` (force-delete orphaned secrets), and
  `ENIIPValidationHook` (verify EKS ENI IPs before cross-VPC DNS apply).

- **`engine`** — DAG-based execution engine. `Graph` provides topological sort, wave
  decomposition (for parallel execution), graph reversal (for teardown), environment
  filtering, and transitive dependent calculation (for failure propagation). `Engine`
  dispatches units via in-degree counting, runs hooks, persists state atomically to JSON
  after each unit completes, and skips transitive dependents on failure. `TerragruntRunner`
  executes `terragrunt apply/destroy` subprocesses with provider-specific environment
  variables and classifies errors (SCP violations, state lock conflicts). `Logger` creates
  timestamped per-run log directories with per-unit log files and `run.json` metadata.

- **`cloud`** — Abstracts provider-specific API calls behind `Client` and `AWSClient`
  interfaces. The `AWS` implementation uses the AWS CLI (not the SDK) for secret existence
  checks, force-deletion, and EKS ENI IP lookups.

- **`validate`** — Health-check framework with `Checker` interface, parallel bounded
  execution, two-phase validation (IAM gate), and prefix-based filtering. Includes checks
  for EKS cluster status, K8s workload readiness, SecretStore status, ArgoCD app sync/health,
  TGW attachment state, cross-VPC DNS resolution, Gateway health, DNS delegation,
  Tailscale connectivity, and HTTP endpoints.

### Configuration

All runtime configuration lives in `.platctl.yaml` at the repository root:

```yaml
environments:
  platform:
    path: infra/live/aws/platform/us-east-1/platform
    provider: aws
    auth:
      profile: management

overrides:
  platform/eks:
    bootstrap_args: ["-var", "endpoint_public_access=true"]
  platform/tailscale:
    hook: crd_two_stage
    hook_target: "helm_release.tailscale_operator[0]"

lockdown:
  - unit: platform/eks
    description: "Disable public endpoint after Tailscale is operational"
```

Unit names are qualified as `<env>/<unit>` (e.g., `platform/eks`, `preprod/networking`).
Dependencies are auto-discovered from `terragrunt.hcl` files; `implicit_deps` in overrides
add cross-environment edges that Terragrunt cannot express.

## Consequences

### Positive

- **Reproducible deploys.** The execution order is deterministic and derived from the same
  dependency graph that Terragrunt uses. No manual ordering mistakes.
- **Resumability.** Failed runs can be continued with `--resume` instead of re-running from
  scratch, saving 20-30 minutes on partial failures.
- **Parallel execution.** Independent units run concurrently (bounded by `--concurrency`),
  reducing total deploy time compared to sequential scripts.
- **Built-in validation.** `platctl validate` catches issues (expired SSO sessions, unhealthy
  pods, broken DNS delegation) before they surface as mysterious Terraform errors.
- **Hook system.** CRD bootstrapping, secret cleanup, and ENI validation are encoded as typed
  hooks rather than ad-hoc shell commands, making them testable and documented.
- **Failure isolation.** When a unit fails, only its transitive dependents are skipped.
  Independent branches of the DAG continue executing.
- **Per-unit logging.** Each run creates a timestamped directory with per-unit log files and
  run metadata, making post-mortem debugging straightforward.

### Negative

- **Go dependency.** The platform team must maintain a Go module (`cmd/platctl/`) alongside
  the HCL/Terragrunt codebase. The Go toolchain is already required for Terratest, so this
  is incremental rather than net-new.
- **Sync with Terragrunt config.** If a new unit is added to the live config, it is
  auto-discovered. However, new hook types, manual steps, or lockdown steps require updates
  to both `.platctl.yaml` and potentially the Go code. The auto-discovery of dependencies
  from `terragrunt.hcl` files minimizes this, but overrides are still manual.
- **AWS CLI dependency.** The `cloud` package shells out to the AWS CLI rather than using the
  SDK. This keeps the dependency tree small but means the CLI inherits the AWS CLI's
  authentication behavior and error messages.

### Risks

- If `terragrunt.hcl` dependency blocks use expressions that the HCL parser cannot statically
  evaluate (e.g., `config_path` referencing a local variable), auto-discovery will miss those
  edges. All current units use string literals, but this assumption should be documented.
- The shell-based runner captures stdout/stderr into a buffer. Units with very large output
  (e.g., verbose Terraform plans) may consume significant memory during parallel execution.
