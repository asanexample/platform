# Onboarding Guide

Welcome to the multi-cloud infrastructure repository. This guide walks you
through everything you need to get productive: installing prerequisites,
understanding the repository layout, deploying your first stack, and making
your first change.

> **New here?** Skim the [Glossary](glossary.md) for the platform vocabulary, and
> [Identity & SSO](architecture/identity-and-sso.md) for how login/permissions work
> (it's the part most people find confusing). For "I can't log in," go straight to
> [SSO Troubleshooting](runbooks/identity-sso-troubleshooting.md).

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
sso_start_url = https://d-XXXXXXXXXX.awsapps.com/start
sso_region = us-east-1
sso_registration_scopes = sso:account:access

[profile management]
sso_session = centric
sso_account_id = <MGMT_ACCOUNT_ID>
sso_role_name = AdministratorAccess

[profile platform]
sso_session = centric
sso_account_id = <PLATFORM_ACCOUNT_ID>
sso_role_name = AdministratorAccess
```

Developers should also add:

```ini
[profile platform-dev]
sso_session = centric
sso_account_id = <PLATFORM_ACCOUNT_ID>
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

### ArgoCD Access

ArgoCD is the platform's continuous delivery tool, available at
`https://argocd.aws.refplat.org`. You must be connected to the Tailscale
VPN to access ArgoCD.

**Login:** Click "Log in via SSO" on the login page. You will be redirected to
AWS Identity Center. Authenticate with your Identity Center credentials and
you will be returned to ArgoCD with permissions based on your group membership:

| Identity Center Group | ArgoCD Access |
|----------------------|---------------|
| Admins | Full admin -- manage all apps, clusters, and repositories |
| Developers | Sync and view applications, view logs |
| ReadOnly | Read-only access to all resources |

**Admin password:** The local `admin` account is available as break-glass only.
Retrieve the password with:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

See [ArgoCD SSO](runbooks/argocd-sso.md) for setup and troubleshooting.

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
│   ├── root.hcl                       # Root config: providers, remote state (S3), global tags
│   │
│   ├── modules/                       # Reusable OpenTofu modules (AWS only today; azure/, gcp/ planned)
│   │   ├── aws/                       # AWS-specific: organizations, state_bootstrap, networking,
│   │   │                              #   eks, eks-addons, ecr, cloudtrail, transit-gateway, s3, ...
│   │   ├── argocd/ argocd-apps/       # Shared (cloud-agnostic) modules:
│   │   ├── cilium/ cert-manager/      #   CNI, GitOps, TLS, DNS, secrets, gateway, policy (Kyverno),
│   │   ├── external-dns/ external-secrets/  #   observability, observability-mimir, environment, tailscale,
│   │   ├── policy/ observability/     #   secret-stores, cluster-rbac, eks-pod-identity, vcluster (deferred)
│   │   └── ...
│   │
│   ├── live/                          # Terragrunt live configurations
│   │   └── aws/                       # (only cloud deployed; live/azure, live/gcp are planned)
│   │       ├── _base.hcl              # Composer: loads layers, composes tags, safety assertions
│   │       ├── _versions.hcl          # Module source paths and Helm version pins
│   │       ├── common.hcl             # Cloud-wide defaults; loads secrets.hcl (gitignored)
│   │       ├── mgmt/                  # Management account (<MGMT_ACCOUNT_ID>)
│   │       │   ├── env.hcl            # Environment-level config
│   │       │   └── global/{state-bootstrap,organizations,identity-center}/
│   │       ├── platform/  us-east-1/  # Platform account — the hub cluster + shared services
│   │       ├── preprod/   us-east-1/  # Preprod account — environment workloads
│   │       ├── prod/      us-east-1/  # Prod account
│   │       └── test/      global/     # Terratest sandbox account
│   │
│   ├── tests/                         # Terratest (Go) module integration tests
│   ├── scripts/                       # Helper scripts and hooks
│   └── docs/                          # Infrastructure design docs (numbered 00-20)
│
└── cmd/platctl/                       # The platctl orchestration CLI (Go, ADR-038)
```

---

## Configuration Hierarchy

Terragrunt uses a six-layer configuration hierarchy where each layer can
override values from layers above it. This eliminates duplication while
allowing per-environment customization. (`_versions.hcl` and `_base.hcl` are
supporting files loaded by the composer, not hierarchy layers — see
[config-hierarchy.md](architecture/config-hierarchy.md).)

The layers, from broadest to narrowest scope:

1. **Root** (`infra/root.hcl`) -- Remote state (S3), AWS provider, global tags
2. **Cloud** (`infra/live/aws/common.hcl`) -- Cloud-wide defaults, loads secrets.hcl, account mapping
3. **Environment** (`infra/live/aws/{env}/env.hcl`) -- Account ID, environment tags, classification
4. **Region** (`infra/live/aws/{env}/{region}/region.hcl` + `network.hcl`) -- Region, abbreviation, CIDRs
5. **Workload** (`infra/live/aws/{env}/{region}/{workload}/workload.hcl`) -- Workload name, compliance tier
6. **Unit** (`infra/live/aws/{env}/{region}/{workload}/{unit}/terragrunt.hcl`) -- Final inputs, dependencies

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
aws s3 ls s3://tfstate-mgmt-<MGMT_ACCOUNT_ID>
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
#   + aws_organizations_account.this["test"]
#   + aws_organizations_account.this["preprod"]
#   + aws_organizations_account.this["prod"]
#   + aws_organizations_policy.this["baseline-guardrails"]
#   ... (7 SCPs total, + optional hipaa-eligible-services)

# Apply
terragrunt apply
```

State for this module is stored remotely in the S3 bucket created in Step 1.

### Step 3: Deploy the Platform Stack

With the management account set up, deploy the full platform stack (EKS,
networking, Cilium, ArgoCD, Tailscale, observability, and all supporting
services) using **`platctl`** (the Go orchestration CLI, ADR-038):

```bash
# Prerequisites:
#   - AWS SSO login completed (aws sso login --profile management)
#   - CLOUDFLARE_API_TOKEN exported

platctl bootstrap            # or: platctl bootstrap --dry-run / --resume
```

`platctl` auto-discovers all (~30) Terragrunt units and applies them in
dependency order with parallel execution. It handles the private-endpoint
bootstrap problem (temporarily enables public access, locks down after
Tailscale is deployed) and prompts for two manual steps:

1. **Tailscale account setup** -- create an account, generate an API key, and
   store it in Secrets Manager
2. **ArgoCD SAML app** -- create a SAML application in AWS Identity Center
   (SSO URL and CA cert are pre-configured in `infra/live/aws/common.hcl`)

`platctl` is resumable -- if it fails partway through, `platctl bootstrap --resume`
picks up where it left off.

To tear down the entire stack:

```bash
platctl teardown
```

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

## Deploying Applications

Development teams deploy applications to the preprod EKS cluster via ArgoCD.
Each team gets an isolated namespace with resource quotas and network policies
enforced.

### Quick Start

1. **Push images** to ECR via GitHub Actions (OIDC auth, no credentials needed):

   ```text
   <PLATFORM_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/team-<name>/app:<tag>
   ```

2. **Commit manifests** to your team's repo at `k8s/preprod/` (Deployment,
   Service, HTTPRoute).

3. **ArgoCD auto-syncs** your manifests to preprod.

4. **Access your app** at `https://<app>.preprod.aws.refplat.org`.

5. **Debug** with namespace-scoped kubectl:

   ```bash
   platctl kubeconfig --env preprod
   kubectl --context preprod get pods -n team-<name>
   ```

For the full guide, see [Deploy App to Preprod](runbooks/deploy-app-preprod.md).

For platform engineers onboarding new teams, see
[Environment Onboarding](runbooks/environment-onboarding.md).

---

## Next Steps

Once you have completed your first deploy:

1. Read the [User Guide](user-guide.md) for in-depth module configuration and day-2 operations.
2. Review the [Architecture Decision Records](adrs/) to understand the reasoning behind key design choices.
3. Explore the [infrastructure design docs](../infra/docs/) (numbered `00` through `20`) for deep-dives into networking, security, Kubernetes, and more.
4. Check `docs/runbooks/` for any operational procedures relevant to your work.
