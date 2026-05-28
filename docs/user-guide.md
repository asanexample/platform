# User Guide

This document is the end-to-end reference for configuring, deploying, and
operating the AWS infrastructure managed by this repository. It covers module
configuration, greenfield and brownfield deployment paths, day-2 operations,
and integration patterns between modules.

---

## Table of Contents

1. [Module Configuration Reference](#module-configuration-reference)
2. [Common Customizations](#common-customizations)
3. [Greenfield Deployment](#greenfield-deployment)
4. [Brownfield Deployment](#brownfield-deployment)
5. [Day-2 Operations](#day-2-operations)
6. [Integration with Other Modules](#integration-with-other-modules)
7. [Variable Reference Tables](#variable-reference-tables)

---

## Module Configuration Reference

### State Bootstrap Module

The state bootstrap module creates the S3 bucket and DynamoDB table that serve
as the Terraform remote state backend. It is always deployed first, with a
local backend.

Minimal configuration:

```hcl
# infra/live/aws/mgmt/global/state-bootstrap/terragrunt.hcl
include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders()
}

remote_state {
  backend = "local"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    path = "${get_terragrunt_dir()}/terraform.tfstate"
  }
}

terraform {
  source = include.base.locals.module_source.state_bootstrap
}

inputs = {
  bucket_name         = "tfstate-mgmt-851725353202"
  dynamodb_table_name = "terraform-locks"
  tags                = include.base.locals.tags
}
```

The `remote_state` block overrides the root-level S3 backend with a local
backend. This is necessary because the S3 bucket does not exist yet.

### Organizations Module

The organizations module manages the full AWS Organizations hierarchy:
the organization itself, organizational units, member accounts, and Service
Control Policies.

Minimal configuration (data-source an existing organization):

```hcl
inputs = {
  create              = true
  create_organization = false   # Use existing org (data source)
  tags                = include.base.locals.tags

  organizational_units = {
    "Platform"  = { parent = null }
    "Workloads" = { parent = null }
  }
}
```

Full configuration with all options:

```hcl
inputs = {
  create              = true
  create_organization = true    # Create the org (greenfield only)
  tags                = include.base.locals.tags

  allowed_regions = ["us-east-1", "us-west-2"]
  required_tags   = ["Environment", "ManagedBy", "Owner"]
  exempt_roles    = ["OrganizationAccountAccessRole", "BreakGlassRole"]
  enable_hipaa_scp = true

  organization_aws_service_access_principals = [
    "cloudtrail.amazonaws.com",
    "config.amazonaws.com",
    "guardduty.amazonaws.com",
    "securityhub.amazonaws.com",
    "access-analyzer.amazonaws.com",
    "sso.amazonaws.com",
    "tagpolicies.tag.amazonaws.com",
  ]

  organization_enabled_policy_types = ["SERVICE_CONTROL_POLICY", "TAG_POLICY"]

  organizational_units = {
    "Platform"            = { parent = null }
    "Workloads"           = { parent = null }
    "Workloads/Preprod"   = { parent = "Workloads" }
    "Workloads/Prod"      = { parent = "Workloads" }
    "Workloads/Regulated" = { parent = "Workloads" }
  }

  accounts = {
    "platform" = { email = "aws+platform@example.com", ou = "Platform" }
    "preprod"  = { email = "aws+preprod@example.com",  ou = "Workloads/Preprod" }
    "prod"     = { email = "aws+prod@example.com",     ou = "Workloads/Prod" }
  }

  scp_attachments = {
    "root"      = ["baseline-guardrails", "protect-security-services", "enforce-encryption", "deny-regions"]
    "Platform"  = ["protect-data-and-network"]
    "Workloads" = ["protect-data-and-network", "require-tagging", "restrict-iam-users"]
  }

  # Override built-in SCPs entirely (advanced):
  # service_control_policies = {
  #   "custom-policy" = jsonencode({ ... })
  # }
}
```

---

## Common Customizations

### Adding Allowed Regions

By default, the region-deny SCP restricts resources to `us-east-1` and
`us-west-2`. To allow additional regions, update the `allowed_regions` input:

```hcl
inputs = {
  allowed_regions = ["us-east-1", "us-west-2", "eu-west-1", "eu-central-1"]
}
```

Global services (IAM, Route 53, CloudFront, Organizations, and others) are
always exempt from region restrictions regardless of this setting. See the
`deny-regions` SCP in `scps.tf` for the full exemption list.

### Changing Required Tags

The `require-tagging` SCP denies the creation of EC2 instances, S3 buckets,
and RDS instances that lack the specified tags. Update the list:

```hcl
inputs = {
  required_tags = ["Environment", "ManagedBy", "Owner", "CostCenter", "DataClassification"]
}
```

Each tag generates an independent deny statement, so adding or removing a tag
does not affect enforcement of the others.

### Enabling the HIPAA SCP

The HIPAA eligible services SCP restricts the organization to only those AWS
services that are covered under the AWS Business Associate Addendum. Enable it
with:

```hcl
inputs = {
  enable_hipaa_scp = true
}
```

When enabled, this SCP is added to the `default_scps` map and must still be
attached to a target through `scp_attachments`. For example:

```hcl
inputs = {
  enable_hipaa_scp = true
  scp_attachments = {
    "root"                = ["baseline-guardrails", "protect-security-services", "enforce-encryption", "deny-regions"]
    "Workloads/Regulated" = ["protect-data-and-network", "require-tagging", "restrict-iam-users", "hipaa-eligible-services"]
  }
}
```

### Adding Exempt Roles

Exempt roles bypass SCP deny statements. The default exempt role is
`OrganizationAccountAccessRole`. To add additional roles (for example, a
break-glass emergency role):

```hcl
inputs = {
  exempt_roles = ["OrganizationAccountAccessRole", "BreakGlassRole"]
}
```

The module constructs wildcard ARN patterns from these names
(`arn:aws:iam::*:role/RoleName`), so the exemption applies across all accounts.

### Custom SCP Overrides

To completely replace all built-in SCPs with your own policies, use the
`service_control_policies` variable:

```hcl
inputs = {
  service_control_policies = {
    "my-custom-policy" = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Sid       = "DenyAllS3"
          Effect    = "Deny"
          Action    = "s3:*"
          Resource  = "*"
        }
      ]
    })
  }
}
```

When this variable is non-null, **all** built-in SCPs are replaced. The
`scp_attachments` variable must reference only the policy names defined in
your custom map.

---

## Greenfield Deployment

A greenfield deployment starts from scratch with no existing AWS Organization
or state backend. Follow these steps in order.

### Prerequisites

- AWS credentials with administrative access to the management account
- All tools installed (see [Onboarding Guide](onboarding.md#prerequisites))

### Step 1: Deploy the State Bootstrap

```bash
cd infra/live/aws/mgmt/global/state-bootstrap

# Initialize Terragrunt and OpenTofu
terragrunt init

# Preview the resources
terragrunt plan

# Create the S3 bucket and DynamoDB table
terragrunt apply
```

Expected resources created:

- S3 bucket `tfstate-mgmt-851725353202` with versioning, KMS encryption, and public access block
- DynamoDB table `terraform-locks` with PAY_PER_REQUEST billing and `LockID` hash key

### Step 2: Deploy AWS Organizations

```bash
cd infra/live/aws/mgmt/global/organizations

# Initialize (this uses the S3 backend from Step 1)
terragrunt init

# Preview
terragrunt plan

# Create the organization, OUs, accounts, and SCPs
terragrunt apply
```

Expected resources created:

- AWS Organization with `ALL` features
- 5 organizational units (Platform, Workloads, Workloads/Preprod, Workloads/Prod, Workloads/Regulated)
- 2 member accounts (platform, preprod)
- 7 Service Control Policies (baseline-guardrails, protect-security-services, enforce-encryption, deny-regions, protect-data-and-network, require-tagging, restrict-iam-users)
- SCP attachments to root and OUs

### Step 3: Deploy the Platform Stack

With the management account configured, deploy the full platform stack using
the bootstrap script. This deploys all 16 Terragrunt units (networking, EKS,
Cilium, node groups, Tailscale, ArgoCD, and all supporting services) in
dependency order.

```bash
# Prerequisites:
#   - AWS SSO login completed
#   - CLOUDFLARE_API_TOKEN exported
./scripts/bootstrap-platform.sh
```

The script prompts for two manual steps during execution:

1. **Tailscale account setup** (after node groups are deployed) -- create an
   account, generate an API key, store it in Secrets Manager
2. **ArgoCD SAML app** (after Tailscale is deployed) -- create a SAML app in
   Identity Center. SSO URL and CA cert are pre-configured in
   `infra/live/aws/common.hcl`

The script is idempotent. Re-running after a failure picks up where it left
off -- already-applied units complete in seconds with no changes.

### Step 4: Verify

```bash
# Verify management account
aws organizations describe-organization
ROOT_ID=$(aws organizations list-roots --query 'Roots[0].Id' --output text)
aws organizations list-organizational-units-for-parent --parent-id "$ROOT_ID"
aws organizations list-accounts
aws organizations list-policies --filter SERVICE_CONTROL_POLICY

# Verify platform stack (connect to Tailscale first)
kubectl get nodes
kubectl get pods -A
```

### Teardown

To destroy the full platform stack:

```bash
./scripts/teardown-platform.sh                  # preserves Route53 zone
./scripts/teardown-platform.sh --include-route53  # destroys everything
```

The teardown script requires typing `DESTROY` to confirm. It enables the
public EKS endpoint before destroying K8s resources (since Tailscale is
destroyed first), then waits 5 minutes for DNS propagation. Route53 is
preserved by default because destroying the zone requires re-creating the
Cloudflare NS delegation.

---

## Brownfield Deployment

A brownfield deployment adopts an existing AWS Organization and its accounts
into Terragrunt management. This involves importing existing resources into
state so that OpenTofu can manage them going forward without attempting to
recreate them.

### Prerequisites

Gather the following identifiers from your existing organization:

| Resource | Identifier | Example Value |
|----------|-----------|---------------|
| Organization | Organization ID | `o-a4kjvito7o` |
| Organization root | Root ID | Find via `aws organizations list-roots` |
| Platform account | Account ID | `829808296602` |
| Preprod account | Account ID | `620830101009` |
| Existing OUs | OU IDs | Find via `aws organizations list-organizational-units-for-parent` |

### Step 1: Deploy State Bootstrap

The state bootstrap is always a greenfield operation (you cannot import an S3
bucket into a state file that does not exist yet).

```bash
cd infra/live/aws/mgmt/global/state-bootstrap
terragrunt apply
```

### Step 2: Configure Organizations for Brownfield

Set `create_organization = false` so the module data-sources the existing
organization instead of creating a new one:

```hcl
# infra/live/aws/mgmt/global/organizations/terragrunt.hcl
inputs = {
  create              = true
  create_organization = false   # Data-source existing org
  tags                = include.base.locals.tags
  # ... rest of configuration
}
```

### Step 3: Initialize and Import

```bash
cd infra/live/aws/mgmt/global/organizations
terragrunt init
```

Import the existing organization:

```bash
# Import the organization (not needed when create_organization = false,
# since the module uses a data source instead of a resource)

# Import organizational units
terragrunt import 'aws_organizations_organizational_unit.this["Platform"]' ou-xxxx-xxxxxxxx
terragrunt import 'aws_organizations_organizational_unit.this["Workloads"]' ou-xxxx-yyyyyyyy
terragrunt import 'aws_organizations_organizational_unit.this["Workloads/Preprod"]' ou-xxxx-zzzzzzzz
# ... repeat for each OU

# Import accounts
terragrunt import 'aws_organizations_account.this["platform"]' 829808296602
terragrunt import 'aws_organizations_account.this["preprod"]' 620830101009
```

### Step 4: Plan and Verify

After all imports, run a plan to verify that OpenTofu recognizes the existing
resources and does not want to recreate them:

```bash
terragrunt plan
```

The plan should show **zero** additions and **zero** destructions for imported
resources. You may see updates for tags or other attributes that differ from
the declared configuration; review these carefully.

If the plan shows resources to create, you likely missed an import. If it shows
resources to destroy, the configuration may not match reality -- adjust your
inputs to match the existing state before applying.

### Step 5: Import SCPs

SCPs are created by the module, so they do not need to be imported in most
brownfield scenarios. However, if you have existing SCPs that match the
module's names, you can import them:

```bash
# List existing SCPs
aws organizations list-policies --filter SERVICE_CONTROL_POLICY

# Import if names match
terragrunt import 'aws_organizations_policy.this["baseline-guardrails"]' p-xxxxxxxxxxxx
```

### Step 6: Apply

Once the plan is clean (no unintended changes), apply to bring tags and
SCP attachments into alignment:

```bash
terragrunt apply
```

---

## Day-2 Operations

### Adding a New Account

1. Add the account to the `accounts` map in the organizations Terragrunt config:

```hcl
accounts = {
  "platform" = { email = "aws+platform@example.com", ou = "Platform" }
  "preprod"  = { email = "aws+preprod@example.com",  ou = "Workloads/Preprod" }
  "prod"     = { email = "aws+prod@example.com",     ou = "Workloads/Prod" }  # NEW
}
```

1. Plan and review:

```bash
cd infra/live/aws/mgmt/global/organizations
terragrunt plan
# Expected: + aws_organizations_account.this["prod"]
```

1. Apply:

```bash
terragrunt apply
```

The new account will be created and placed in the specified OU. AWS sends a
verification email to the email address provided. The account inherits all
SCPs attached to its parent OU.

### Moving an Account Between OUs

To move an account to a different OU, change the `ou` field:

```hcl
accounts = {
  "preprod" = { email = "aws+preprod@example.com", ou = "Workloads/Prod" }  # Changed from Workloads/Preprod
}
```

Plan and apply. The account will be moved to the new OU, and the SCPs attached
to the new OU will take effect.

### Adding a New Organizational Unit

Add the OU to the `organizational_units` map:

```hcl
organizational_units = {
  "Platform"            = { parent = null }
  "Workloads"           = { parent = null }
  "Workloads/Preprod"   = { parent = "Workloads" }
  "Workloads/Prod"      = { parent = "Workloads" }
  "Workloads/Regulated" = { parent = "Workloads" }
  "Sandbox"             = { parent = null }           # NEW top-level OU
  "Sandbox/Dev"         = { parent = "Sandbox" }      # NEW nested OU
}
```

Nested OUs reference their parent by name. The `parent = null` value places the
OU directly under the organization root.

### Updating SCPs

#### Modifying a Built-in SCP

Edit the policy document in `infra/modules/aws/organizations/scps.tf`. For
example, to add a new deny statement to the baseline guardrails:

```hcl
statement {
  sid       = "DenyNewAction"
  effect    = "Deny"
  actions   = ["some-service:DangerousAction"]
  resources = ["*"]
}
```

Plan and apply from the organizations live directory. The SCP resource will
show as modified.

#### Changing SCP Attachments

To change which SCPs are attached to which targets, update the
`scp_attachments` map:

```hcl
scp_attachments = {
  "root"      = ["baseline-guardrails", "protect-security-services", "enforce-encryption", "deny-regions"]
  "Platform"  = ["protect-data-and-network"]
  "Workloads" = ["protect-data-and-network", "require-tagging", "restrict-iam-users"]
  "Sandbox"   = ["baseline-guardrails", "deny-regions"]  # NEW: lighter policy set for sandbox
}
```

#### Adding a Completely New SCP

If the built-in SCPs are not sufficient, you have two options:

**Option A: Override all SCPs** (use `service_control_policies` to replace the entire set).

**Option B: Extend the module** by adding a new `data "aws_iam_policy_document"` block in `scps.tf`, adding it to the `default_scps` local, and referencing it in `scp_attachments`.

### Removing an Account

AWS does not allow programmatic deletion of organization member accounts.
To remove an account from Terragrunt management without closing it:

```bash
# Remove from state
terragrunt state rm 'aws_organizations_account.this["account-name"]'

# Remove from the accounts map in terragrunt.hcl
# Then plan and apply to confirm no other changes
```

Note that `close_on_deletion = false` is set on all accounts in this module,
so even if you did a `terragrunt destroy`, the accounts would be removed from
state but not closed.

---

## Integration with Other Modules

The organizations module produces outputs that are consumed by account-level
configurations throughout the repository.

### Outputs Available

| Output | Type | Description | Downstream Use |
|--------|------|-------------|---------------|
| `organization_id` | `string` | The org ID (e.g., `o-a4kjvito7o`) | Cross-account trust policies |
| `organization_arn` | `string` | The org ARN | IAM condition keys |
| `root_id` | `string` | The org root ID | SCP attachment targets |
| `ou_ids` | `map(string)` | OU name to OU ID mapping | Account placement, SCP targets |
| `ou_arns` | `map(string)` | OU name to OU ARN mapping | IAM policies scoped to OUs |
| `account_ids` | `map(string)` | Account name to account ID mapping | Cross-account roles, provider configs |
| `account_arns` | `map(string)` | Account name to account ARN mapping | IAM trust policies |
| `scp_ids` | `map(string)` | SCP name to SCP ID mapping | Audit and compliance reporting |

### Consuming Org Outputs in Other Modules

Use Terragrunt `dependency` blocks to reference organizations outputs from
downstream modules:

```hcl
# Example: infra/live/aws/ops/us-east-1/platform/networking/terragrunt.hcl
dependency "org" {
  config_path = "../../../../mgmt/global/organizations"
}

inputs = {
  account_id      = dependency.org.outputs.account_ids["platform"]
  organization_id = dependency.org.outputs.organization_id
}
```

### Account-Level Provider Configuration

To deploy resources into a member account, the AWS provider assumes the
`PlatformDeployer` role. This is configured globally in `root.hcl` and
referenced via `include.base.locals.deployer_role_arn` in Helm/K8s providers:

```hcl
# root.hcl — provider automatically assumes PlatformDeployer
provider "aws" {
  region = "us-east-1"
  assume_role {
    role_arn = "arn:aws:iam::${local.aws_account_id}:role/PlatformDeployer"
  }
}
```

### IAM Roles

The platform uses purpose-built IAM roles instead of the default
`OrganizationAccountAccessRole`. See [ADR-007](adrs/007-iam-role-model.md)
for the design rationale.

| Role | Account | Purpose |
|------|---------|---------|
| **PlatformAdmin** | Platform | kubectl, SSM tunnel, cluster debugging |
| **PlatformDeployer** | Platform | Terragrunt apply, Helm/K8s providers |
| **DeveloperAccess** | Platform | Namespace-scoped kubectl for developers |
| **TerraformStateAccess** | Management | S3 state + DynamoDB lock table |
| **OrganizationAccountAccessRole** | All accounts | Break-glass only |

For cluster access procedures, see the
[EKS Cluster Access runbook](runbooks/eks-cluster-access.md).

### State Bootstrap Integration

The state bootstrap module's outputs (bucket name, DynamoDB table name) are
consumed by the root `terragrunt.hcl` to configure the S3 backend for all
other modules. This is a hard-coded reference rather than a Terragrunt
dependency, because the state backend must be configured before any module
can initialize:

```hcl
# infra/root.hcl (root)
remote_state {
  backend = "s3"
  config = {
    bucket         = "tfstate-mgmt-851725353202"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}
```

---

## Variable Reference Tables

### State Bootstrap Module Variables

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `create` | `bool` | `true` | No | Whether to create the state storage resources. Set to `false` to disable the module entirely. |
| `bucket_name` | `string` | -- | **Yes** | Name of the S3 bucket for Terraform state. Must be globally unique. Convention: `tfstate-{env}-{account_id}`. |
| `dynamodb_table_name` | `string` | `"terraform-locks"` | No | Name of the DynamoDB table for state locking. |
| `tags` | `map(string)` | `{}` | No | Tags to apply to the S3 bucket and DynamoDB table. |

### State Bootstrap Module Outputs

| Output | Type | Description |
|--------|------|-------------|
| `bucket_name` | `string` | Name of the S3 state bucket. |
| `bucket_arn` | `string` | ARN of the S3 state bucket. |
| `dynamodb_table_name` | `string` | Name of the DynamoDB lock table. |
| `dynamodb_table_arn` | `string` | ARN of the DynamoDB lock table. |

### Organizations Module Variables

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `create` | `bool` | `true` | No | Whether to create any resources in this module. |
| `create_organization` | `bool` | `false` | No | Whether to create the AWS Organization. Set to `false` to data-source an existing one. |
| `organization_aws_service_access_principals` | `list(string)` | See below | No | AWS service principals to enable for organization integration. |
| `organization_enabled_policy_types` | `list(string)` | `["SERVICE_CONTROL_POLICY", "TAG_POLICY"]` | No | Policy types to enable in the organization. |
| `organizational_units` | `map(object({parent = optional(string)}))` | `{}` | No | Map of OU names to their configuration. `parent = null` for root-level OUs. |
| `accounts` | `map(object({email = string, ou = optional(string)}))` | `{}` | No | Map of account names to their configuration. `ou` references an OU key from `organizational_units`. |
| `service_control_policies` | `map(string)` | `null` | No | Custom SCP JSON map override. When non-null, replaces **all** built-in default SCPs. |
| `scp_attachments` | `map(list(string))` | See below | No | Map of target name to list of SCP names to attach. Use `"root"` for the org root. |
| `allowed_regions` | `list(string)` | `["us-east-1", "us-west-2"]` | No | AWS regions where resources are allowed (used by `deny-regions` SCP). |
| `required_tags` | `list(string)` | `["Environment", "ManagedBy", "Owner"]` | No | Tag keys that must be present on supported resources (used by `require-tagging` SCP). |
| `exempt_roles` | `list(string)` | `["OrganizationAccountAccessRole"]` | No | IAM role names exempt from SCP deny statements. |
| `enable_hipaa_scp` | `bool` | `false` | No | Whether to enable the HIPAA eligible services allowlist SCP. |
| `tags` | `map(string)` | `{}` | No | Tags to apply to SCPs and OUs. |

**Default `organization_aws_service_access_principals`:**

```text
cloudtrail.amazonaws.com, config.amazonaws.com, guardduty.amazonaws.com,
securityhub.amazonaws.com, access-analyzer.amazonaws.com, sso.amazonaws.com,
tagpolicies.tag.amazonaws.com
```

**Default `scp_attachments`:**

```hcl
{
  "root"      = ["baseline-guardrails", "protect-security-services", "enforce-encryption", "deny-regions"]
  "Platform"  = ["protect-data-and-network"]
  "Workloads" = ["protect-data-and-network", "require-tagging", "restrict-iam-users"]
}
```

### Organizations Module Outputs

| Output | Type | Description |
|--------|------|-------------|
| `organization_id` | `string` | The ID of the AWS Organization. |
| `organization_arn` | `string` | The ARN of the AWS Organization. |
| `root_id` | `string` | The ID of the organization root. |
| `ou_ids` | `map(string)` | Map of OU names to their IDs. |
| `ou_arns` | `map(string)` | Map of OU names to their ARNs. |
| `account_ids` | `map(string)` | Map of account names to their IDs. |
| `account_arns` | `map(string)` | Map of account names to their ARNs. |
| `scp_ids` | `map(string)` | Map of SCP names to their IDs. |

---

## Application Deployment (Preprod)

Development teams deploy applications to the preprod EKS cluster via ArgoCD
GitOps. Each team gets an isolated namespace or vCluster with resource quotas
and network policies enforced.

### ECR Container Registry

Images are stored in ECR in the platform account (829808296602) and pulled
cross-account by preprod (620830101009) and prod (554518885123).

```bash
# Authenticate to ECR
aws ecr get-login-password --region us-east-1 --profile platform \
  | docker login --username AWS --password-stdin 829808296602.dkr.ecr.us-east-1.amazonaws.com

# Push an image
docker tag myapp:latest 829808296602.dkr.ecr.us-east-1.amazonaws.com/team-alpha/app:v1.0.0
docker push 829808296602.dkr.ecr.us-east-1.amazonaws.com/team-alpha/app:v1.0.0
```

ECR repos are defined in `infra/live/aws/platform/us-east-1/platform/ecr/terragrunt.hcl`.
GitHub Actions pushes via OIDC federation — no static credentials needed.

### Tenant Management

Teams are defined in `infra/live/aws/preprod/us-east-1/platform/teams.hcl`.
Two isolation modes are available:

| Mode | Namespace | Isolation | Best For |
|------|-----------|-----------|----------|
| `namespace` | `team-<name>` | Cilium NetworkPolicy | Trusted teams, simple apps |
| `vcluster` | `vc-<name>` | Full virtual control plane | CRD independence, strong isolation |

See [Tenant Onboarding](runbooks/tenant-onboarding.md) for the full
onboarding procedure.

### Developer Workflow

See [Deploy App to Preprod](runbooks/deploy-app-preprod.md) for the complete
developer guide including repo structure, sample manifests, ECR push, and
debugging.
