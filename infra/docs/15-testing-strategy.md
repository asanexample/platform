# Testing Strategy

## Overview

The platform standardizes on **Terratest (Go)** for module testing — full
apply/destroy cycles with AWS SDK-based assertions where post-apply state must
be validated, and **plan-only** Terratest for modules that cannot be safely
apply/destroyed in CI. Terraform native tests (`.tftest.hcl`) are **not** used
(see [Testing Conventions](../../CLAUDE.md#testing-conventions)). Only AWS is
deployed today; Azure/GCP module tests will follow the same Terratest approach
when those clouds land. CI runs static checks (format, validate, lint, policy)
on every PR; integration tests run on a weekly schedule.

## Testing Principles

1. **Plan-only where possible** -- modules that are expensive to create or
   require elevated permissions use plan-only tests. Apply/destroy tests
   are reserved for modules where post-apply validation is essential.
2. **OpenTofu binary** -- all Terratest options must set
   `TerraformBinary: "tofu"` to match the production toolchain.
3. **Tests live outside modules** -- test files are never colocated with
   module code. AWS tests go in `infra/tests/aws/<module>/`.
4. **Parallel execution** -- Go tests use `t.Parallel()` to run
   concurrently where resource isolation allows.

## Directory Structure

```text
infra/tests/
├── aws/                              # Terratest (Go)
│   ├── go.mod                        # Module deps: terratest, aws-sdk, testify
│   ├── go.sum
│   ├── README.md
│   ├── networking/
│   │   ├── networking_test.go        # Test functions
│   │   ├── helpers_test.go           # AWS clients, fixture helpers, assertions
│   │   └── fixtures/                 # main.tf, provider.tf, versions.tf
│   ├── eks/
│   │   ├── eks_test.go
│   │   ├── helpers_test.go
│   │   └── fixtures/
│   └── ssm-bastion/
│       ├── ssm_bastion_test.go
│       ├── helpers_test.go
│       └── fixtures/
└── helpers/                          # Shared Go helpers (e.g. get_public_ip)
    └── get_public_ip/
```

New module tests are added as a sibling directory under `infra/tests/aws/`.

## AWS Tests (Terratest)

AWS tests use [Terratest](https://terratest.gruntwork.io/) to run
OpenTofu against real AWS infrastructure, then validate results with the
AWS SDK.

### Dependencies

```text
github.com/gruntwork-io/terratest   v0.47.2
github.com/aws/aws-sdk-go          v1.55.8
github.com/stretchr/testify        v1.11.1
```

### Test Patterns

**Full apply/destroy** -- creates real resources, validates with AWS API,
cleans up:

```go
func TestNetworking_PrivateTopology(t *testing.T) {
    t.Parallel()

    moduleDir := copyModuleToTemp(t)
    client := newEC2Client(t)

    vars := map[string]interface{}{
        "create":   true,
        "vpc_name": "test-" + random.UniqueId() + "-vpc",
        // ...
    }

    opts := newTerraformOptions(t, moduleDir, vars)
    defer terraform.Destroy(t, opts)
    terraform.InitAndApply(t, opts)

    vpcID := terraform.Output(t, opts, "vpc_id")
    assert.NotEmpty(t, vpcID)
    assertSubnetPublicIP(t, client, subnetMap["az1-public"], true)
}
```

**Plan-only** -- validates Terraform plan structure without provisioning:

```go
func TestNetworking_Disabled(t *testing.T) {
    t.Parallel()

    opts := newTerraformOptions(t, moduleDir, vars)
    opts.PlanFilePath = filepath.Join(moduleDir, "plan.out")
    planStruct := terraform.InitAndPlanAndShowWithStruct(t, opts)

    assert.Empty(t, planStruct.ResourcePlannedValuesMap,
        "should produce zero resources")
}
```

### When to Use Each Pattern

| Pattern | When to Use | Example |
|---------|-------------|---------|
| Apply/destroy | Must validate actual cloud state (routes, security groups, API responses) | Networking, EKS |
| Plan-only | Validates resource structure, counts, or disabled-module behavior | `create = false` checks, addon plans |

Rule of thumb: if the test calls AWS SDK APIs to assert state, it must be
apply/destroy. If it only inspects the plan structure, use plan-only.

### Helper Conventions

Each test module has a `helpers_test.go` with shared utilities:

| Helper | Purpose |
|--------|---------|
| `newTerraformOptions()` | Build `*terraform.Options` with `TerraformBinary: "tofu"` |
| `copyModuleToTemp()` | Copy module source + fixtures to a temp directory |
| `newEC2Client()` / `newEKSClient()` | Create AWS SDK clients (with optional STS assume-role) |
| `testRegion()` / `testRoleARN()` | Read `TEST_AWS_REGION` / `TEST_ROLE_ARN` env vars with defaults |
| `assert*()` functions | Custom assertions using AWS API (e.g., `assertRouteExists`, `assertSubnetPublicIP`) |

### Fixtures

Test fixtures live in `infra/tests/aws/<module>/fixtures/` and contain
the Terraform entry point (`main.tf`, `provider.tf`, `versions.tf`) that
references the module under test. The `.terraform/` directory is cached in
fixtures to speed up repeated `tofu init` during local development.

## CI Integration

### Every PR (`.github/workflows/ci.yml`)

Static checks + policy + security scanning -- no infrastructure is provisioned:

| Job | What It Checks |
|-----|---------------|
| OpenTofu Format | `tofu fmt -check -recursive infra/modules/` |
| OpenTofu Validate | `tofu init -backend=false` + `tofu validate` on every module |
| TFLint | Linting with `--minimum-failure-severity=error` |
| Terragrunt HCL Format | `terragrunt hcl fmt --check` |
| Markdown Lint | `markdownlint-cli2` on changed `.md` files |
| Kyverno Policy Test | renders the `policy` module's ClusterPolicies and runs `kyverno test` |
| Kyverno Shift-Left (dogfood) | runs the `kyverno-validate` action against compliant/broken sample apps |
| Trivy / Semgrep | IaC misconfig + Go SCA + SAST, blocking on HIGH/CRITICAL |

See [Deployment Workflows](14-deployment-workflows.md#ci-on-every-pr-githubworkflowsciyml)
for the full security-gate detail.

### Weekly (`.github/workflows/test-aws.yml`)

Integration tests run on a schedule (Monday 6:00 UTC) with manual
dispatch available:

| Job | Timeout | Command |
|-----|---------|---------|
| `test-networking` | 30 min | `go test -v -timeout 25m ./networking/...` |
| `test-eks` | 45 min | `go test -v -timeout 40m ./eks/...` |

These jobs authenticate via GitHub OIDC to the test-sandbox Terratest role
(`github-actions-terratest`, supplied through the `TEST_ROLE_ARN` repo variable)
and run in `us-west-2` (the `157263244316` test account — see
[test-sandbox runbook](../../docs/runbooks/test-sandbox-account.md)).

## Running Tests Locally

```bash
# Requires active AWS credentials (PlatformDeployer in the test sandbox account)
cd infra/tests/aws
go test -v -timeout 30m ./networking/...    # Single module
go test -v -timeout 45m ./...               # All AWS tests

# Via Makefile
make test-aws                               # All AWS Terratest (45m timeout)
make test-aws-networking                    # AWS networking (30m timeout)
make test-aws-eks                           # AWS EKS (45m timeout)
make test-platctl                           # platctl Go unit tests
```

## Next Steps

Continue to [Disaster Recovery](16-disaster-recovery.md) to understand how
the Reference Platform handles business continuity and disaster recovery
scenarios.
