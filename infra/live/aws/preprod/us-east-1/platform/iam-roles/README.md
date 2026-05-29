# iam-roles

Bootstraps IAM roles (PlatformAdmin, PlatformDeployer, ArgoCD, and one DeveloperAccess-\<team\> per team) in the preprod account. Must be applied first — all other units depend on these roles for cross-account access.

## Module

`infra/modules/aws/iam_roles`

## Dependencies

None

## Key Inputs

| Input                    | Value                                               | Notes                                                                           |
|--------------------------|-----------------------------------------------------|---------------------------------------------------------------------------------|
| `roles.PlatformAdmin`    | Trust: management + preprod SSO                     | EKS, SSM, Secrets Manager read access; used for kubectl and debugging           |
| `roles.PlatformDeployer` | Trust: management + preprod                         | AdministratorAccess managed policy; used by Terragrunt for all provisioning     |
| `roles.ArgoCD`           | Trust: platform account (<PLATFORM_ACCOUNT_ID>)              | Scoped to platform's ArgoCD IRSA role; enables cross-account cluster management |
| `roles.DeveloperAccess-<team>` | Trust: that team's `Dev-<team>` SSO permission set | One per team (from `teams.hcl`); namespace-scoped EKS access via group-mapped RBAC (ADR-039) |

## Commands

```bash
# Plan (direct SSO — bootstraps before cross-account roles exist)
AWS_PROFILE=preprod terragrunt plan

# Apply
AWS_PROFILE=preprod terragrunt apply
```
