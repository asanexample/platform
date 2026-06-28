# IAM Roles

Creates IAM roles with configurable trust policies, managed policy attachments, and inline policies. Designed for creating purpose-built cross-account roles (PlatformAdmin, PlatformDeployer, DeveloperAccess, TerraformStateAccess) that are assumed from a central management account. Each role's trust policy is built from `trust_principals` (AWS principal ARNs and/or a `service` principal such as `pods.eks.amazonaws.com` for EKS Pod Identity) with optional conditions, and `trust_actions` (defaults to `sts:AssumeRole`; Pod Identity roles also need `sts:TagSession`).

## Usage

```hcl
module "iam_roles" {
  source = "../../modules/aws/iam_roles"

  roles = {
    PlatformAdmin = {
      description = "Full cluster admin access for kubectl and debugging"
      trust_principals = {
        aws = ["arn:aws:iam::<MGMT_ACCOUNT_ID>:root"]
      }
      managed_policies = [
        "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
      ]
    }
    PlatformDeployer = {
      description          = "Terragrunt apply, Helm, and K8s providers"
      max_session_duration = 7200
      trust_principals = {
        aws = ["arn:aws:iam::<MGMT_ACCOUNT_ID>:root"]
      }
      managed_policies = [
        "arn:aws:iam::aws:policy/PowerUserAccess",
      ]
      inline_policies = {
        iam-limited = jsonencode({
          Version = "2012-10-17"
          Statement = [{
            Effect   = "Allow"
            Action   = ["iam:PassRole", "iam:GetRole"]
            Resource = "*"
          }]
        })
      }
    }
  }

  tags = {
    Environment = "platform"
    ManagedBy   = "opentofu"
  }
}
```

## Examples

### Disabled Module

```hcl
module "iam_roles" {
  source = "../../modules/aws/iam_roles"
  create = false
}
```

### Role with Trust Conditions

```hcl
module "iam_roles" {
  source = "../../modules/aws/iam_roles"

  roles = {
    DeveloperAccess = {
      description = "Namespace-scoped kubectl for developers"
      trust_principals = {
        aws = ["arn:aws:iam::<MGMT_ACCOUNT_ID>:root"]
      }
      trust_conditions = [
        {
          test     = "StringEquals"
          variable = "aws:PrincipalTag/team"
          values   = ["engineering"]
        }
      ]
    }
  }

  tags = {
    Environment = "platform"
  }
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_iam_role.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_policy_document.trust](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_create"></a> [create](#input\_create) | Whether to create resources in this module | `bool` | `true` | no |
| <a name="input_roles"></a> [roles](#input\_roles) | Map of IAM roles to create | <pre>map(object({<br/>    description          = optional(string, "")<br/>    path                 = optional(string, "/")<br/>    max_session_duration = optional(number, 3600)<br/>    # Map of principal type -> identifiers. Keys: "aws" (AWS account/role ARNs), "service" (AWS service<br/>    # principals, e.g. "pods.eks.amazonaws.com" for EKS Pod Identity), "federated".<br/>    trust_principals = map(list(string))<br/>    # Trust-policy actions. Defaults to sts:AssumeRole; Pod Identity needs ["sts:AssumeRole","sts:TagSession"].<br/>    trust_actions = optional(list(string), ["sts:AssumeRole"])<br/>    trust_conditions = optional(list(object({<br/>      test     = string<br/>      variable = string<br/>      values   = list(string)<br/>    })), [])<br/>    # Additional trust statements, OR-ed with the primary one above. Use when a role must trust a second<br/>    # principal under DIFFERENT conditions — e.g. PlatformDeployer's primary statement is SSO-admin-only, but<br/>    # it must ALSO admit the ARC runner role (no SSO condition). Same principal/condition shape as above.<br/>    extra_trust_statements = optional(list(object({<br/>      actions    = optional(list(string), ["sts:AssumeRole"])<br/>      principals = map(list(string))<br/>      conditions = optional(list(object({<br/>        test     = string<br/>        variable = string<br/>        values   = list(string)<br/>      })), [])<br/>    })), [])<br/>    managed_policies = optional(list(string), [])<br/>    inline_policies  = optional(map(string), {})<br/>    tags             = optional(map(string), {}) # merged onto var.tags (e.g. { Team = "alpha" })<br/>  }))</pre> | `{}` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_role_arns"></a> [role\_arns](#output\_role\_arns) | Map of role name to ARN |
| <a name="output_role_names"></a> [role\_names](#output\_role\_names) | Map of role name to IAM role name |
<!-- END_TF_DOCS -->

## Notes

- The `trust_principals` map keys by principal type: `aws` (IAM/account ARNs), `service` (AWS service principals, e.g. `pods.eks.amazonaws.com` for EKS Pod Identity), and `federated`. `trust_actions` defaults to `["sts:AssumeRole"]`; Pod Identity roles set `["sts:AssumeRole","sts:TagSession"]`.
- Managed policies and inline policies are both optional and default to empty.
- Role names are used as the map keys and become the actual IAM role names in AWS.
- Default max session duration is 3600 seconds (1 hour); increase for long-running Terragrunt applies.

## Related ADRs

- ADR-007: Platform IAM Role Model
