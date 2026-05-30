# Code Review Findings — 2026-05-29

Consolidated findings from a full codebase review covering shared modules, AWS modules, live Terragrunt configs, platctl CLI, tests, scripts, and CI.

---

## 1. Add mutex to platctl `State`

**Severity:** Critical
**Files:** `cmd/platctl/internal/engine/state.go`, `cmd/platctl/internal/engine/state_test.go`

`MarkRunning`/`MarkCompleted`/`MarkFailed` are called from goroutines while `Save` concurrently serializes via `json.MarshalIndent`. This is a real data race that can corrupt the state file under parallel execution. The test `TestFileStore_ConcurrentWrites` confirms the race under `-race`.

**Prompt:**
```
Fix the data race in cmd/platctl/internal/engine/state.go. The State struct's Mark* methods are called from goroutines while Save concurrently reads the struct for JSON marshaling. Add a sync.RWMutex to State — write-lock in MarkRunning, MarkCompleted, MarkFailed, MarkSkipped, and read-lock in Save (take a snapshot under the lock before marshaling). Also fix TestFileStore_ConcurrentWrites in state_test.go so it passes under -race. Run `go test -race ./cmd/platctl/internal/engine/...` to verify.
```

---

## 2. Add `mock_outputs` to identity-center dependency

**Severity:** Critical
**File:** `infra/live/aws/mgmt/global/identity-center/terragrunt.hcl`

The `dependency "organizations"` block is the only dependency in the entire codebase without `mock_outputs`. This breaks `terragrunt destroy` if organizations is already gone.

**Prompt:**
```
Add mock_outputs to the organizations dependency in infra/live/aws/mgmt/global/identity-center/terragrunt.hcl. Look at the organizations module outputs (infra/modules/aws/organizations/outputs.tf) and provide appropriate mock values for each output. Follow the same mock_outputs pattern used by other dependencies in the codebase (e.g., infra/live/aws/platform/us-east-1/platform/cilium/terragrunt.hcl). Add mock_outputs_allowed_terraform_commands = ["validate", "plan", "destroy"].
```

---

## 3. Fix CI versions (Go, OpenTofu)

**Severity:** Critical
**File:** `.github/workflows/test-aws.yml`

`GO_VERSION` is "1.22" but `go.mod` declares 1.26.2. `TOFU_VERSION` is "1.9.0" but the project uses 1.11.x. CI builds will fail or produce divergent results.

**Prompt:**
```
Update .github/workflows/test-aws.yml to align tool versions with the project:
- Set GO_VERSION to match the version in go.mod
- Set TOFU_VERSION to "1.11.6" to match what the project uses (check infra/root.hcl or existing state files for the exact version)
Also check .github/workflows/ci.yml for any stale version references and fix those too.
```

---

## 4. Delete dead scripts

**Severity:** Critical
**Files:** `scripts/migrate-state-to-workload-hierarchy.sh`, `infra/scripts/hooks/`, `infra/scripts/scaffold_region.sh`

- `migrate-state-to-workload-hierarchy.sh` is entirely Azure-specific, references removed infrastructure.
- `infra/scripts/hooks/az-remote-state-init` is entirely Azure-specific.
- `scaffold_region.sh` calls 5 undefined functions and references removed cloud providers — broken at runtime.

**Prompt:**
```
Delete these dead/broken scripts:
- scripts/migrate-state-to-workload-hierarchy.sh (Azure-only, references removed infra)
- infra/scripts/hooks/ directory (az-remote-state-init is Azure-only dead code)
- infra/scripts/scaffold_region.sh (calls undefined functions, references removed cloud providers)

Also clean up stale Azure test artifacts:
- infra/tests/README.md (describes removed Azure .tftest.hcl framework — rewrite it to describe the current Terratest approach, or delete it and rely on infra/tests/aws/README.md)
- infra/tests/provider_local.tf.template (Azure credentials template)
- infra/tests/mock_values.tfvars (Azure mock values)

Check if infra/tests/provider_local.tf or infra/tests/terraform.tfvars exist on disk with Azure credentials and warn me (don't commit those).
```

---

## 5. Add `versions.tf` to 14 AWS modules

**Severity:** Warning
**Affected:** cloudtrail, ecr, eks, eks-node-group, github_oidc, iam_roles, identity_center, networking, organizations, route53, route53_delegation, ssm-bastion, state_bootstrap, transit-gateway

Only `cross-vpc-dns` and `eks-addons` have `versions.tf`. The other 14 have no provider or terraform version constraints.

**Prompt:**
```
Add versions.tf to every AWS module under infra/modules/aws/ that is missing one. The 14 modules are: cloudtrail, ecr, eks, eks-node-group, github_oidc, iam_roles, identity_center, networking, organizations, route53, route53_delegation, ssm-bastion, state_bootstrap, transit-gateway.

Use this template, adjusting required_providers based on what each module actually uses (check main.tf for provider references):

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

Only include providers that the module actually uses. For example, identity_center only needs aws; organizations only needs aws. Don't add providers the module doesn't reference.
```

---

## 6. Remove undeclared inputs

**Severity:** Warning
**Files:** `infra/root.hcl`, multiple terragrunt.hcl units

Several inputs are passed to modules that don't declare the corresponding variables:
- `root.hcl:71-79` passes `common_tags` to every module — no module has this variable
- `root.hcl:99-105` defines unused `common_tags` local
- Networking units pass `environment`, `workload`, `region_abbv` — not declared in networking module
- Secret-stores units pass `tags` — not declared in secret-stores module
- argocd-apps unit passes `cluster_name` — not declared in argocd-apps module

**Prompt:**
```
Clean up undeclared inputs being passed to modules:

1. In infra/root.hcl: remove the `inputs` block (lines 71-79) that passes `common_tags` — no module declares this variable. Also remove the dead `common_tags` local (lines 99-105) if it exists.

2. In the networking terragrunt units (infra/live/aws/platform/us-east-1/platform/networking/terragrunt.hcl, same in preprod and prod): remove the `environment`, `workload`, and `region_abbv` inputs — the networking module doesn't declare these variables.

3. In the secret-stores terragrunt units (platform and preprod): remove the `tags` input — the secret-stores module has no `tags` variable. Alternatively, add a `tags` variable to infra/modules/secret-stores/variables.tf if tags should be applied.

4. In infra/live/aws/platform/us-east-1/platform/argocd-apps/terragrunt.hcl: remove the `cluster_name` input — the argocd-apps module has no such variable.

For each removal, verify the variable truly doesn't exist in the target module's variables.tf before removing. Run `terragrunt validate` from one of the affected unit directories afterward.
```

---

## 7. Remove unused variables from cilium and tenant modules

**Severity:** Warning
**Files:** `infra/modules/cilium/variables.tf`, `infra/modules/tenant/variables.tf`

Cilium has 7 unused variables: `environment`, `workload`, `region_abbv`, `cluster_name`, `resource_group_name`, `cni_exclusive`, `prometheus_service_monitor_enabled`. Tenant has 2: `environment`, `region_abbv`. Also remove the unused AWS provider declaration from cilium's `versions.tf`.

**Prompt:**
```
Remove unused variables from shared modules:

1. In infra/modules/cilium/variables.tf, remove these variables (verify each is unreferenced in main.tf/outputs.tf first via grep): environment, workload, region_abbv, cluster_name, resource_group_name, cni_exclusive, prometheus_service_monitor_enabled.

2. In infra/modules/cilium/versions.tf, remove the aws provider from required_providers — the module creates no AWS resources (only uses helm and null providers).

3. In infra/modules/tenant/variables.tf, remove: environment, region_abbv.

After removing variables from modules, search all terragrunt.hcl files that source these modules and remove the corresponding inputs so they don't pass values to nonexistent variables. Check:
- grep -r "environment\|workload\|region_abbv\|cluster_name\|resource_group_name\|cni_exclusive\|prometheus_service_monitor" infra/live/aws/*/us-east-1/*/cilium/terragrunt.hcl
- grep -r "environment\|region_abbv" infra/live/aws/*/us-east-1/*/tenants/terragrunt.hcl

Run `terragrunt validate` from a cilium and tenant unit directory to verify.
```

---

## 8. Standardize provider version constraints

**Severity:** Warning
**Files:** All `versions.tf` files across modules

Current inconsistencies:
- `required_version`: `>= 1.5` (argocd-apps) vs `>= 1.6.0` (everything else)
- `kubernetes`: `>= 2.10.0` (tenant, vcluster) to `>= 3.0` (argocd-apps)
- `aws`: `>= 5.0` (most) vs `>= 6.0` (tailscale-admin) vs `~> 6.0` (eks-addons)
- `helm`: `>= 2.9.0` to `>= 2.17.0`

**Prompt:**
```
Standardize provider version constraints across all modules (both infra/modules/ and infra/modules/aws/).

Target versions (use the highest floor that works):
- required_version = ">= 1.6.0"
- aws = ">= 5.0" (change tailscale-admin from >= 6.0 and eks-addons from ~> 6.0)
- kubernetes = ">= 2.35.0" (update tenant from >= 2.10.0, vcluster from >= 2.10.0)
- helm = ">= 2.17.0" (standardize across all helm-using modules)

Find all versions.tf files: find infra/modules -name versions.tf
Update each one. Don't change provider source attributes, only version constraints.
```

---

## 9. Upgrade secret-stores to `v1` API

**Severity:** Warning
**File:** `infra/modules/secret-stores/main.tf`

Uses `external-secrets.io/v1beta1` for `ClusterSecretStore` manifests, but the external-secrets chart version deployed is 0.14.3, which supports `v1`. The `v1beta1` API is deprecated.

**Prompt:**
```
In infra/modules/secret-stores/main.tf, update the apiVersion on all kubernetes_manifest resources from "external-secrets.io/v1beta1" to "external-secrets.io/v1". The external-secrets-operator chart deployed (0.14.3) supports v1. Verify by checking the CRD docs or the chart's crds/ directory. Run `terragrunt plan` from a secret-stores unit to confirm no unexpected changes.
```

---

## 10. Scope IAM policies (networking flow log, external-secrets path prefix)

**Severity:** Warning
**Files:** `infra/modules/aws/networking/main.tf`, `infra/modules/external-secrets/variables.tf`

- Networking flow log IAM policy uses `Resource = "*"` for CloudWatch Logs — should scope to the specific log group ARN.
- external-secrets default `secret_path_prefix = "*"` grants access to all secrets in the account.

**Prompt:**
```
Tighten two overly permissive IAM scopes:

1. In infra/modules/aws/networking/main.tf, find the aws_iam_role_policy.flow_log resource. Change Resource = "*" to scope it to the specific log group ARN: aws_cloudwatch_log_group.flow_log[0].arn and "${aws_cloudwatch_log_group.flow_log[0].arn}:*". Also remove the logs:CreateLogGroup action since the log group is already created by Terraform.

2. In infra/modules/external-secrets/variables.tf, change the default for secret_path_prefix from "*" to something more restrictive like "platform/" or remove the default entirely to force callers to specify a path prefix. Check all callers (grep for secret_path_prefix in infra/live/) to make sure they explicitly set this value.
```
