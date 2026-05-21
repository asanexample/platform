# Onboarding Guide

Welcome to the multi-cloud infrastructure repository. This guide walks you
through everything you need to get productive: installing prerequisites,
understanding the repository layout, deploying your first stack, and making
your first change.

---

## Prerequisites

### Required Tools

Install the following before you begin. Versions listed are minimums; newer
patch releases are fine.

| Tool | Minimum Version | Purpose |
|------|-----------------|---------|
| [OpenTofu](https://opentofu.org/docs/intro/install/) | >= 1.6.0 | Infrastructure-as-code engine (Terraform-compatible) |
| [Terragrunt](https://terragrunt.gruntwork.io/docs/getting-started/install/) | >= 0.55.0 | Configuration orchestration, DRY wrappers around OpenTofu |
| [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) | >= 2.x | AWS API interactions and credential management |
| Git | >= 2.30 | Version control |

### AWS Credentials

Access is managed through AWS IAM Identity Center (SSO). You need two profiles
configured -- one for infrastructure provisioning (management account) and one
for cluster access (platform account).

Add the following to `~/.aws/config`:

```ini
[sso-session centric]
sso_start_url = https://d-9067aa6520.awsapps.com/start
sso_region = us-east-1
sso_registration_scopes = sso:account:access

[profile management]
sso_session = centric
sso_account_id = 851725353202
sso_role_name = AdministratorAccess

[profile platform]
sso_session = centric
sso_account_id = 829808296602
sso_role_name = AdministratorAccess
```

Developers should also add:

```ini
[profile platform-dev]
sso_session = centric
sso_account_id = 829808296602
sso_role_name = PowerUserAccess
```

Log in and verify:

```bash
# For Terragrunt operations
aws sso login --profile management
AWS_PROFILE=management aws sts get-caller-identity

# For cluster access
aws sso login --profile platform
AWS_PROFILE=platform aws sts get-caller-identity
```

See [EKS Cluster Access](runbooks/eks-cluster-access.md) for kubectl setup.

### Verify Tool Versions

```bash
tofu version      # Should print >= 1.6.0
terragrunt -v     # Should print >= 0.55.0
aws --version     # Should print aws-cli/2.x
```

---

## Repository Structure

```text
.
├── docs/                              # User-facing documentation (you are here)
│   ├── README.md                      # Documentation index
│   ├── onboarding.md                  # This file
│   ├── user-guide.md                  # Complete operational reference
│   ├── adrs/                          # Architecture Decision Records
│   ├── architecture/                  # System design documents
│   ├── compliance/                    # Regulatory and audit artifacts
│   ├── runbooks/                      # Step-by-step operational procedures
│   └── troubleshooting/              # Known issues and solutions
│
├── infra/
│   ├── terragrunt.hcl                 # Root config: providers, remote state, global tags
│   │
│   ├── modules/                       # Reusable OpenTofu modules
│   │   ├── aws/
│   │   │   ├── organizations/         # AWS Organizations, OUs, SCPs
│   │   │   ├── state_bootstrap/       # S3 + DynamoDB for remote state
│   │   │   ├── naming/                # AWS resource naming conventions
│   │   │   └── networking/            # VPCs, subnets, routing
│   │   ├── azure/                     # Azure modules (AKS, networking, etc.)
│   │   ├── gcp/                       # GCP modules (networking, naming)
│   │   ├── argocd/                    # ArgoCD deployment
│   │   ├── cilium/                    # Cilium CNI
│   │   ├── policy/                    # Cross-cloud policy engine
│   │   └── vcluster/                  # Virtual Kubernetes clusters
│   │
│   ├── live/                          # Terragrunt live configurations
│   │   ├── aws/
│   │   │   ├── _base.hcl             # Shared AWS base config (config hierarchy)
│   │   │   ├── _versions.hcl         # Module source paths and version pins
│   │   │   ├── common.hcl            # Cloud-wide defaults and account mapping
│   │   │   ├── mgmt/                  # Management account (851725353202)
│   │   │   │   ├── common.hcl        # Environment-level config
│   │   │   │   └── global/
│   │   │   │       ├── state-bootstrap/   # Remote state backend (deploy first)
│   │   │   │       └── organizations/     # AWS Org, OUs, accounts, SCPs
│   │   │   └── platform/              # Platform account (829808296602)
│   │   ├── azure/                     # Azure environments (dev, ops)
│   │   └── gcp/                       # GCP environments (ops)
│   │
│   ├── tests/                         # Module integration tests
│   ├── scripts/                       # Helper scripts and hooks
│   └── docs/                          # Infrastructure design docs (numbered)
│
├── charts/                            # Helm charts
└── planning/                          # Planning and strategy documents
```

---

## Configuration Hierarchy

Terragrunt uses a seven-layer configuration hierarchy where each layer can
override values from layers above it. This eliminates duplication while
allowing per-environment customization.

The layers, from broadest to narrowest scope:

1. **Root** (`infra/root.hcl`) -- Remote state backends, provider versions, global tags
2. **Cloud** (`infra/live/aws/common.hcl`) -- Cloud-wide defaults, account mapping, project tags
3. **Environment** (`infra/live/aws/{env}/common.hcl`) -- Account IDs, environment tags, classification
4. **Region** (`infra/live/aws/{env}/{region}/region.hcl`) -- Region name, abbreviation, region-specific tags
5. **Workload** (`infra/live/aws/{env}/{region}/{workload}/workload.hcl`) -- Workload name, compliance tier
6. **Defaults** (`infra/live/aws/_envcommon/*.hcl`) -- Shared module defaults across environments
7. **Module** (`infra/live/aws/{env}/{region}/{workload}/{module}/terragrunt.hcl`) -- Final overrides

Tags merge across all layers, with narrower scopes winning on conflict. For
example, an environment-level `DataClassification = "Confidential"` overrides a
cloud-level `DataClassification = "Internal"`.

The base config (`infra/live/aws/_base.hcl`) loads all layers and includes
safety validations that verify the directory path matches the configured
environment and that account IDs match the expected mapping.

For a complete deep-dive on how these layers interact, see the comments in
`infra/live/aws/_base.hcl`.

---

## First Deploy Walkthrough

A greenfield deployment follows a strict order: the state backend must exist
before any other module can store its state remotely.

### Step 1: Deploy the State Bootstrap

The state bootstrap module creates the S3 bucket and DynamoDB table that all
other modules use for remote state. It uses a local backend (because the
remote backend does not exist yet).

```bash
cd infra/live/aws/mgmt/global/state-bootstrap

# Review what will be created
terragrunt plan

# Expected output:
#   + aws_s3_bucket.state
#   + aws_s3_bucket_versioning.state
#   + aws_s3_bucket_server_side_encryption_configuration.state
#   + aws_s3_bucket_public_access_block.state
#   + aws_dynamodb_table.locks

# Apply the changes
terragrunt apply

# Verify the bucket exists
aws s3 ls s3://tfstate-mgmt-851725353202
```

After this step, the state file lives locally at
`infra/live/aws/mgmt/global/state-bootstrap/terraform.tfstate`. This is
expected -- see the state bootstrap module README for the chicken-and-egg
explanation.

### Step 2: Deploy Organizations

With remote state available, deploy the AWS Organizations configuration:

```bash
cd infra/live/aws/mgmt/global/organizations

# Review what will be created
terragrunt plan

# Expected output:
#   + aws_organizations_organization.this
#   + aws_organizations_organizational_unit.this["Platform"]
#   + aws_organizations_organizational_unit.this["Workloads"]
#   + aws_organizations_organizational_unit.this["Workloads/Preprod"]
#   + aws_organizations_organizational_unit.this["Workloads/Prod"]
#   + aws_organizations_organizational_unit.this["Workloads/Regulated"]
#   + aws_organizations_account.this["platform"]
#   + aws_organizations_account.this["preprod"]
#   + aws_organizations_policy.this["baseline-guardrails"]
#   ... (7 SCPs total)

# Apply
terragrunt apply
```

State for this module is stored remotely in the S3 bucket created in Step 1.

---

## How to Make a Change

Every infrastructure change follows the same workflow: edit, plan, review,
apply.

### 1. Edit

Make your changes in the appropriate file. Module logic lives in
`infra/modules/`, while environment-specific inputs live in `infra/live/`.

```bash
# Example: add a new account to the organization
# Edit: infra/live/aws/mgmt/global/organizations/terragrunt.hcl
```

### 2. Plan

Run `terragrunt plan` from the module directory to preview changes:

```bash
cd infra/live/aws/mgmt/global/organizations
terragrunt plan
```

Review the plan output carefully. Look for:

- Resources being **destroyed** (marked with `-`)
- Resources being **replaced** (marked with `-/+`)
- Any changes to SCPs or OU structure

### 3. Review

Open a pull request with your changes. The PR should include:

- The Terragrunt/OpenTofu files you changed
- A copy of the plan output in the PR description
- Justification for the change

### 4. Apply

After approval, apply from the module directory:

```bash
terragrunt apply
```

For changes that span multiple modules, use `terragrunt run-all` from a parent
directory, but exercise caution -- always run `run-all plan` first.

---

## Where to Find Things

| I want to... | Go to... |
|---|---|
| Understand **why** a decision was made | `docs/adrs/` -- Architecture Decision Records |
| Understand **how** the system is designed | `docs/architecture/` and `infra/docs/02-architecture-overview.md` |
| Follow a **procedure** step-by-step | `docs/runbooks/` |
| Configure or deploy a **module** | `docs/user-guide.md` and individual module READMEs |
| Prove **compliance** to an auditor | `docs/compliance/` and `infra/docs/10-compliance-framework.md` |
| Debug a **problem** | `docs/troubleshooting/` and `infra/docs/18-troubleshooting.md` |
| See what **modules** are available | `infra/docs/17-available-modules.md` |
| Understand **naming** conventions | `infra/docs/11-naming-conventions.md` |
| Understand **tagging** requirements | `infra/docs/12-tagging-strategy.md` |

---

## Common First-Day Tasks

### View the current organization structure

```bash
aws organizations list-roots
aws organizations list-organizational-units-for-parent --parent-id r-xxxx
aws organizations list-accounts
```

### Run a plan without applying

```bash
cd infra/live/aws/mgmt/global/organizations
terragrunt plan
```

### See what is currently in remote state

```bash
cd infra/live/aws/mgmt/global/organizations
terragrunt state list
```

### Plan all modules in an environment

```bash
cd infra/live/aws/mgmt
terragrunt run-all plan
```

### Read the SCPs that are currently enforced

The default SCPs are defined in `infra/modules/aws/organizations/scps.tf`. To
see the rendered JSON of any SCP:

```bash
cd infra/live/aws/mgmt/global/organizations
terragrunt state show 'aws_organizations_policy.this["baseline-guardrails"]'
```

### Check which account you are authenticated as

```bash
aws sts get-caller-identity
```

### Explore module variables and their defaults

Each module has a `variables.tf` with descriptions and defaults. The module
READMEs contain formatted variable reference tables:

- [Organizations Module](../infra/modules/aws/organizations/README.md)
- [State Bootstrap Module](../infra/modules/aws/state_bootstrap/README.md)

---

## Next Steps

Once you have completed your first deploy:

1. Read the [User Guide](user-guide.md) for in-depth module configuration and day-2 operations.
2. Review the [Architecture Decision Records](adrs/) to understand the reasoning behind key design choices.
3. Explore the [infrastructure design docs](../infra/docs/) (numbered `00` through `20`) for deep-dives into networking, security, Kubernetes, and more.
4. Check `docs/runbooks/` for any operational procedures relevant to your work.
