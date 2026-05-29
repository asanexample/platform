# ADR-007: Platform IAM Role Model

**Date:** 2026-05-20

**Status:** Accepted (DeveloperAccess refined into per-team roles in ADR-039; PlatformAdmin rescoped to operate-not-author in ADR-040)

## Context

The platform originally used `OrganizationAccountAccessRole` -- the default role created by AWS
Organizations -- as a single credential for all operations: Terragrunt providers, Helm providers,
kubectl access, SSM tunnel scripts, state backend access, and shell hooks. This role has full
administrative access to each member account.

This caused two recurring problems:

1. **Fragile kubectl authentication.** The auth chain (management profile -> assume
   OrganizationAccountAccessRole -> get-token) was overwritten every time `eks-tunnel.sh` or
   `aws eks update-kubeconfig` ran. Engineers had to manually fix kubeconfig after each session.

2. **No separation of privilege.** Running `kubectl get pods` required the same credentials that
   could delete the entire AWS account. There was no way to give developers cluster access without
   granting them full account admin.

As the platform matures toward multi-tenancy, we need purpose-built roles that separate
infrastructure provisioning from human cluster access, and support namespace-scoped developer
access.

### Alternatives Considered

**1. Status quo with better kubeconfig management.** Fix the kubeconfig overwrite issue with
wrapper scripts or shell aliases. This solves the fragility problem but not the least-privilege
problem. Rejected because it defers the harder problem and doesn't prepare for developer access.

**2. Single scoped-down role.** Create one new role with reduced permissions (EKS, SSM, read-only
EC2). Use it for both Terragrunt and kubectl. Simpler to implement, but conflates machine and
human access patterns. Terragrunt needs AdministratorAccess-equivalent permissions while kubectl
doesn't.

**3. Full role model (chosen).** Create purpose-built roles for each access pattern: platform
admin (kubectl), deployer (Terragrunt), developer (namespace-scoped kubectl), and state access
(S3/DynamoDB). More IAM complexity, but cleanly separates concerns and scales to multi-tenancy.

## Decision

Create four purpose-built IAM roles, each scoped to a specific access pattern:

| Role | Account | Purpose | EKS Access |
|------|---------|---------|------------|
| **PlatformAdmin** | Platform, PreProd | kubectl, SSM tunnel, operate/debug (not author) | AmazonEKSViewPolicy + `platform-operator` group (ADR-040) |
| **PlatformDeployer** | Platform | Terragrunt apply, Helm providers | AmazonEKSClusterAdminPolicy (cluster) |
| **DeveloperAccess-\<team\>** | Preprod | Namespace-scoped kubectl, one role per team | Group-mapped RBAC (see ADR-039) |
| **TerraformStateAccess** | Management | S3 state + DynamoDB locks | None |

`OrganizationAccountAccessRole` is retained as a break-glass credential, permanently mapped in
EKS access entries and SCP exemptions.

### Trust Boundaries

- **PlatformAdmin:** Trusts management and platform/preprod accounts. Condition restricts to
  AdministratorAccess SSO roles. **Rescoped to operate/observe, not author** (ADR-040): AWS
  ReadOnlyAccess minus secret/data exfil + bastion-scoped SSM; K8s read + debug + operate (no
  cluster-admin). Authoring flows through pipelines (`PlatformDeployer`/ArgoCD); break-glass for emergencies.
- **PlatformDeployer:** Trusts management account only (Terragrunt always runs from the
  management profile). Condition restricts to AdministratorAccess SSO role. Starts with
  `AdministratorAccess` managed policy to avoid regression; scope down in a follow-up.
- **DeveloperAccess-\<team\>:** One role per team (generated from `teams.hcl`). Trusts management
  and preprod accounts, with the condition restricting to that team's own SSO permission set
  (`Dev-<team>`) — so a developer can assume only their own team's role. The original single
  `DeveloperAccess` role (assumable by any PowerUser/Admin and scoped to the union of all team
  namespaces) was replaced; see ADR-039.
- **TerraformStateAccess:** Trusts PlatformDeployer roles across all accounts. Scoped to
  S3 and DynamoDB state resources only.

### Authentication Flows

**Platform engineer (kubectl):**

```text
aws sso login --profile platform -> PlatformAdmin -> eks get-token -> EKS
```

**Platform engineer (Terragrunt):**

```text
aws sso login --profile management -> PlatformDeployer -> Helm/K8s providers
                                   -> TerraformStateAccess -> S3 state
```

**Developer (kubectl):**

```text
aws sso login (Dev-<team> permission set) -> DeveloperAccess-<team> -> eks get-token -> EKS (own namespace only)
```

## Consequences

**Positive:**

- kubectl auth no longer breaks when scripts modify kubeconfig -- each persona has its own
  stable role ARN
- Developers can get namespace-scoped cluster access without account admin
- Infrastructure provisioning credentials are never used for interactive access
- State backend access is isolated to a minimal-privilege role
- Break-glass path preserved via OrganizationAccountAccessRole

**Negative:**

- Four new IAM roles to manage and audit
- PlatformDeployer starts with AdministratorAccess (must scope down later)
- Deployment ordering has chicken-and-egg constraints: roles must exist before providers
  can reference them
- SCP exemption list grows (PlatformDeployer must be exempt alongside OrganizationAccountAccessRole)

**Risks:**

- If TerraformStateAccess trust policy is misconfigured, all Terragrunt operations fail across
  all environments. Mitigated by deploying state-access last and testing incrementally.
- Per-team DeveloperAccess roles, their EKS access entries, and RBAC bindings are now generated
  from `teams.hcl` (the single source of truth); the matching SSO permission sets/groups remain a
  manual step in the mgmt identity-center unit. See ADR-039 and the tenant-onboarding runbook.
