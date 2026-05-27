# platctl

Platform orchestration CLI for multi-environment Terragrunt deployments.

platctl auto-discovers Terragrunt units from `terragrunt.hcl` files, builds a dependency graph, and executes operations in topological order with parallel execution of independent units.

## Installation

```bash
# From the repo root
cd cmd/platctl && go build -o ../../bin/platctl

# Or use Make
make build-platctl

# Or install globally
cd cmd/platctl && go install
```

## Quick Start

```bash
# Preview the execution plan
platctl bootstrap --dry-run

# Deploy everything (both environments)
platctl bootstrap

# Deploy a single environment
platctl bootstrap --env platform

# Tear down
platctl teardown
```

## Commands

### `platctl bootstrap`

Deploys all Terragrunt units in dependency order.

| Flag | Description |
|------|-------------|
| `--env <name>` | Target a single environment (e.g., `platform`, `preprod`) |
| `--dry-run` | Preview the execution plan without running terragrunt |
| `--resume` | Continue from a previous incomplete run |
| `--yes` | Skip manual step prompts (assume prerequisites are met) |

**What it does:**

1. Reads `.platctl.yaml` for environment and override configuration
2. Scans environment directories for `terragrunt.hcl` files
3. Parses `dependency` blocks to build a DAG
4. Executes units in topological order, running independent units in parallel
5. Applies lockdown steps (e.g., disabling public EKS endpoint) after all units complete

### `platctl teardown`

Destroys all Terragrunt units in reverse dependency order (dependents first).

Same flags as `bootstrap` (`--env`, `--dry-run`, `--resume`, `--yes`).

### `platctl status`

Shows the state of the last operation by reading `.platctl-state.json`.

```text
Operation: bootstrap
Started:   2026-05-26 14:30:00

  ok platform/networking                 (23s)
  ok platform/iam-roles                  (18s)
  !! platform/eks                        (45s)  exit code 1
  -- platform/cilium
  -- platform/node-groups

  Completed: 2  Failed: 1  Skipped: 2  Pending: 0  Running: 0
```

### `platctl validate`

Extension point for infrastructure health checks. Currently prints a placeholder message. Cloud-specific checks (EKS status, node readiness, Helm releases) will be added in a future release.

## Environment Filtering

- `--env platform`: runs only platform environment units. Cross-env dependencies are assumed to already exist (terragrunt resolves from remote state).
- `--env preprod`: same for preprod.
- No flag: runs both environments, interleaving as the DAG dictates.

## Resumability

When a unit fails, platctl:

1. Marks the failed unit and its transitive dependents as skipped
2. Lets in-flight parallel units finish (doesn't kill mid-apply)
3. Saves state to `.platctl-state.json`
4. Prints the resume command

To continue after fixing the issue:

```bash
platctl bootstrap --resume
```

This skips completed units and retries from where it left off.

To start fresh (re-run everything, ignoring previous state):

```bash
platctl bootstrap
```

To reset state manually:

```bash
rm .platctl-state.json
```

## Manual Steps

Some units require manual prerequisites (API tokens, SAML configuration). platctl checks these automatically before applying the unit:

| Step | Before Unit | What to do |
|------|-------------|------------|
| Cloudflare API token | `platform/cloudflare-dns` | Store token in Secrets Manager |
| Tailscale API key | `platform/tailscale-admin` | Generate key, store in Secrets Manager |
| ArgoCD SAML app | `platform/argocd` | Create SAML app in Identity Center |

If the check passes, the prompt is skipped. Use `--yes` to skip all prompts.

## Hooks

Hooks are pre-apply operations for units that need special handling:

| Hook | Units | What it does |
|------|-------|-------------|
| CRD two-stage | `platform/tailscale`, `preprod/tailscale` | Deploys the Helm operator first (to register CRDs), then the full apply |
| ENI IP validation | `platform/cross-vpc-dns` | Queries live preprod EKS ENI IPs and warns if they don't match the values in the terragrunt config |
| Secret cleanup | `platform/tailscale-admin` | Force-deletes Secrets Manager secrets during teardown so they can be cleanly recreated on next bootstrap |

## Configuration

platctl is configured via `.platctl.yaml` in the repo root. The graph is auto-discovered; the config file only defines what can't be inferred:

- **environments**: paths, providers, and auth credentials
- **overrides**: per-unit auth, bootstrap args, hooks, implicit deps
- **manual_steps**: prerequisites that require user action
- **lockdown**: post-bootstrap hardening steps

See `.platctl.yaml` for the full configuration.

### Adding a new unit

Just create the directory with a `terragrunt.hcl` file. platctl discovers it automatically on the next run.

### Adding a new environment

1. Add the environment to `.platctl.yaml`
2. Create the directory structure
3. Run `platctl bootstrap --env <name>`

## Logging

Every run writes full terragrunt output to disk:

```text
.platctl-logs/
├── latest → 2026-05-26T143000_bootstrap
├── 2026-05-26T143000_bootstrap/
│   ├── run.json
│   ├── 001_platform--iam-roles.log
│   ├── 001_platform--networking.log
│   ├── 002_platform--eks.log
│   └── ...
```

- **Wave numbers** (001, 002): units with the same number ran in parallel
- **`latest` symlink**: `tail -f .platctl-logs/latest/002_platform--eks.log`
- **`run.json`**: operation type, timestamp, git SHA, unit list

## Troubleshooting

### State lock

```text
Error acquiring the state lock
Lock Info:
  ID: a1b2c3d4-...
```

Another process holds the lock. Wait for it to finish, or force-unlock:

```bash
cd <unit-dir> && terragrunt force-unlock <lock-id>
```

### SCP-blocked destroy

Service Control Policies may block deletion of KMS keys, flow logs, etc. platctl detects this and reports which resources are protected. To work around:

```bash
cd <unit-dir>
terragrunt state list | grep aws_kms_key
terragrunt state rm <resource-address>
terragrunt destroy -auto-approve
```

### Expired SSO token

```text
Error: SSOProviderInvalidToken
```

Re-authenticate:

```bash
aws sso login --profile management
```

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for internal design documentation.
