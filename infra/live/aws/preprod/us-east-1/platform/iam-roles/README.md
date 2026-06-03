# iam-roles

Bootstraps the **static platform IAM roles** (PlatformAdmin, PlatformDeployer, crossplane-ecr-provisioner, ArgoCD, and the generic DeveloperAccess) in the preprod account. Must be applied first — all other units depend on these roles for cross-account access.

The per-team `DeveloperAccess-<team>` and `Pod-team-<team>` roles are **no longer** generated here. As of BACK stack P3 the per-team Terragrunt loops were removed; those roles are now provisioned by the Crossplane Tenant Composition (delivered via a `Tenant` claim from the `tenant-claims` unit).

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
| `roles.DeveloperAccess` | Trust: preprod SSO permission set | Generic namespace-scoped EKS access via group-mapped RBAC (ADR-039). Per-team `DeveloperAccess-<team>`/`Pod-team-<team>` roles are provisioned by the Crossplane Tenant Composition, not this unit |

## Commands

```bash
# Plan (direct SSO — bootstraps before cross-account roles exist)
AWS_PROFILE=preprod terragrunt plan

# Apply
AWS_PROFILE=preprod terragrunt apply
```
