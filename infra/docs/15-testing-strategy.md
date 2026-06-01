# Testing Strategy

## Overview

The platform uses a dual testing approach: **Terratest (Go)** for AWS
modules with full apply/destroy cycles and SDK-based assertions, and
**Terraform native tests** (`.tftest.hcl`) for Azure modules with
plan-only validation. CI runs static checks (format, validate, lint) on
every PR; integration tests run on a weekly schedule.

## Testing Principles

1. **Plan-only where possible** -- modules that are expensive to create or
   require elevated permissions use plan-only tests. Apply/destroy tests
   are reserved for modules where post-apply validation is essential.
2. **OpenTofu binary** -- all Terratest options must set
   `TerraformBinary: "tofu"` to match the production toolchain.
3. **Tests live outside modules** -- test files are never colocated with
   module code. AWS tests go in `infra/tests/aws/<module>/`, Azure tests
   in `infra/tests/modules/azure/<module>/`.
4. **Parallel execution** -- Go tests use `t.Parallel()` to run
   concurrently where resource isolation allows.

## Directory Structure

```text
infra/tests/
├── aws/                              # Terratest (Go)
│   ├── go.mod                        # Module deps: terratest, aws-sdk, testify
│   ├── go.sum
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
└── modules/azure/                    # Terraform native tests
    ├── aks_core/
    │   ├── basic.tftest.hcl
    │   ├── advanced.tftest.hcl
    │   └── validation.tftest.hcl
    ├── networking/
    ├── storage_account/
    └── ...                           # One directory per Azure module
```

## AWS Tests (Terratest)

AWS tests use [Terratest](https://terratest.gruntwork.io/) to run
OpenTofu against real AWS infrastructure, then validate results with the
AWS SDK.

### Dependencies

```text
github.com/gruntwork-io/terratest   v0.47.2
github.com/aws/aws-sdk-go          v1.55.8
github.com/stretchr/testify        v1.10.0
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

## Azure Tests (Terraform Native)

Azure tests use Terraform's built-in `terraform test` command with
`.tftest.hcl` files. All Azure tests are **plan-only** -- they validate
resource configuration without creating infrastructure.

```hcl
run "basic_prometheus_dcr" {
  command = plan

  variables {
    resource_group_name  = "test-rg"
    location             = "eastus"
    monitor_workspace_id = "/subscriptions/.../accounts/test-monitor"
  }

  module {
    source = "../../../../modules/azure/prometheus_dcr"
  }

  assert {
    condition     = length(azurerm_monitor_data_collection_rule.this) > 0
    error_message = "DCR should be planned for creation"
  }
}
```

Azure modules with mock dependencies use a `mocks/` subdirectory to
provide fake outputs from upstream modules.

## CI Integration

### Every PR (`.github/workflows/ci.yml`)

Static checks only -- no infrastructure is provisioned:

| Job | What It Checks |
|-----|---------------|
| OpenTofu Format | `tofu fmt -check -recursive infra/modules/` |
| OpenTofu Validate | `tofu init -backend=false` + `tofu validate` on every module |
| TFLint | Linting with `--minimum-failure-severity=error` |
| Terragrunt HCL Format | `terragrunt hcl fmt --check` |
| Markdown Lint | `markdownlint-cli2` on changed `.md` files |

### Weekly (`.github/workflows/test-aws.yml`)

Integration tests run on a schedule (Monday 6:00 UTC) with manual
dispatch available:

| Job | Timeout | Command |
|-----|---------|---------|
| `test-networking` | 30 min | `go test -v -timeout 25m ./networking/...` |
| `test-eks` | 45 min | `go test -v -timeout 40m ./eks/...` |

These jobs authenticate via OIDC to the `github-actions-terratest` IAM
role and run in `us-west-2`.

## Running Tests Locally

```bash
# AWS -- requires active AWS credentials
cd infra/tests/aws
go test -v -timeout 30m ./networking/...    # Single module
go test -v -timeout 45m ./...               # All AWS tests

# Azure -- requires Azure CLI authentication
cd infra/tests/modules/azure/<module>
terraform init && terraform test

# Via Makefile
make test-aws-networking                    # AWS networking (30m timeout)
make test-aws-eks                           # AWS EKS (45m timeout)
make test MODULE=aks_core                   # Azure specific module
```

## Next Steps

Continue to [Disaster Recovery](16-disaster-recovery.md) to understand how
the Reference Platform handles business continuity and disaster recovery
scenarios.
