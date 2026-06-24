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
| `--concurrency <n>` | Maximum parallel unit executions (default: 4) |

**Global flags** (available on all subcommands):

| Flag | Description |
|------|-------------|
| `--config <path>` | Path to config file (default: `<repo-root>/.platctl.yaml`) |

**What it does:**

1. Reads `.platctl.yaml` for environment and override configuration
2. Scans environment directories for `terragrunt.hcl` files
3. Parses `dependency` blocks to build a DAG
4. Executes units in topological order, running independent units in parallel
5. Applies lockdown steps (e.g., disabling public EKS endpoint) after all units complete

### `platctl teardown`

Destroys all Terragrunt units in reverse dependency order (dependents first).

Same flags as `bootstrap` (`--env`, `--dry-run`, `--resume`, `--yes`, `--concurrency`).

### `platctl down` / `platctl up`

Park and restore an environment's worker capacity — for dropping an idle environment's cost without a full
teardown.

- `platctl down --env <env>` first **drains Karpenter** — it clears the `karpenter.sh/do-not-disrupt`
  annotation from the pods that carry it (the stateful pods protect themselves from *voluntary* disruption in
  steady state, but that annotation also blocks the termination drain, so a park would otherwise hang on them),
  then deletes the NodePool and **polls until its NodeClaims are actually gone** (the delete cascades to NodeClaim
  deletion in the background and returns early — it does *not* block until the instances terminate) — *then*
  scales every managed node group to `desiredSize=0, minSize=0` via the EKS API. The Karpenter step is essential:
  the
  controller runs on the system group, so scaling the managed groups first would kill it mid-park and leave its
  EC2 instances orphaned (ADR-078). No-op on clusters without Karpenter. The **control plane and all EBS volumes
  survive** (e.g. CNPG databases), so it is non-destructive; `--yes` skips the confirmation.
- `platctl up --env <env>` re-applies the env's `node-groups` unit (restoring the configured sizes from the HCL),
  then **waits for the cluster API to become reachable** (the restored nodes + the in-cluster Tailscale router
  that fronts the private endpoint take a few minutes to come back), then re-applies the **`karpenter` unit**
  (recreating the NodePool `down` deleted, so node autoscaling returns). The readiness gate is essential: the
  karpenter apply needs the helm/kubernetes providers, so applying before the API is up fails *and* orphans
  karpenter's helm releases from TF state (a manual-import trap). On timeout it skips karpenter (node groups are
  already restored) and asks you to re-run.

```bash
platctl down --env preprod    # park overnight (~5-min resume, data intact)
platctl up   --env preprod    # bring it back
```

Cost spectrum by idle duration: minimal-always-on (active testing) → `down` (overnight; control plane + NAT still
bill) → `teardown --env` (idle days+; ~$0, full rebuild to restore). The cluster/region/profile come from the
`kubeconfig:` entry whose `alias` matches the env.

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

Runs health checks against deployed infrastructure. Checks are organized in two phases:

- **Phase 1 (IAM)**: SSO sessions, role assumptions, state backend access. If any fail, Phase 2 is skipped to avoid cascading failures from expired credentials.
- **Phase 2 (Infrastructure)**: Per-unit checks (EKS cluster, K8s workloads, secret stores, ArgoCD apps), cross-cutting checks (gateway, DNS delegation, Tailscale connectivity, endpoints).

| Flag | Description |
|------|-------------|
| `--env <name>` | Target a single environment (e.g., `platform`, `preprod`) |
| `--check <prefixes>` | Run only checks matching these prefixes (comma-separated, e.g., `tailscale,gateway`) |
| `--concurrency <n>` | Maximum parallel checks (default: 8) |

Check types are resolved automatically from unit names — `eks` gets an EKS cluster health check, `cilium` gets a K8s workload check in `kube-system`, etc. Cross-cutting checks (gateway, DNS, Tailscale, endpoints) are configured in the `validate:` section of `.platctl.yaml`.

Every failure includes diagnostics: what failed, raw evidence, likely cause, and fix commands.

```text
$ platctl validate --env platform
Validating 17 units (env: platform)...

  ok iam                                SSO valid, 2/2 deployer roles assumable, state bucket ok
  ok platform/eks                       cluster ACTIVE, 3/3 nodes Ready
  ok platform/cilium                    3/3 pods ready in kube-system
  ok platform/cert-manager              3/3 pods ready in cert-manager
  !! platform/gateway                   TLS NOT ready
     → Certificate platform-gateway-tls: Ready=False, Reason: rate limited
     → Run: kubectl describe certificate platform-gateway-tls -n default
  ok tailscale/platform                 subnet router online, CIDR 10.100.0.0/16 advertised, API reachable
  ok dns/aws.refplat.org                4/4 NS records match

Passed: 26  Failed: 1  Skipped: 0  (2.483s)
```

Use `--check` for fast targeted checks:

```bash
platctl validate --check tailscale          # ~3ms
platctl validate --check gateway,dns        # just gateway + DNS
```

### `platctl kubeconfig`

Configures kubectl contexts for all clusters defined in `.platctl.yaml`.

```bash
platctl kubeconfig                    # configure all clusters
platctl kubeconfig --env platform     # single environment
```

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

- **environments**: paths, providers, and auth credentials (including `region` for AWS API calls)
- **overrides**: per-unit auth, bootstrap args, hooks, implicit deps
- **manual_steps**: prerequisites that require user action
- **lockdown**: post-bootstrap hardening steps

See `.platctl.yaml` for the full configuration.

### AWS region

AWS API calls (Secrets Manager, EC2) use the `region` key from the environment's `auth` map. Defaults to `us-east-1` if not specified:

```yaml
environments:
  platform:
    auth:
      profile: management
      region: us-east-1  # optional, this is the default
```

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
