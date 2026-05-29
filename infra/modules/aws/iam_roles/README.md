# IAM Roles

Creates IAM roles with configurable trust policies, managed policy attachments, and inline policies. Designed for creating purpose-built cross-account roles (PlatformAdmin, PlatformDeployer, DeveloperAccess, TerraformStateAccess) that are assumed from a central management account. Each role's trust policy is built from AWS principal ARNs with optional conditions.

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

No requirements.

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | n/a |

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
| <a name="input_roles"></a> [roles](#input\_roles) | Map of IAM roles to create | <pre>map(object({<br/>    description          = optional(string, "")<br/>    path                 = optional(string, "/")<br/>    max_session_duration = optional(number, 3600)<br/>    trust_principals     = map(list(string))<br/>    trust_conditions = optional(list(object({<br/>      test     = string<br/>      variable = string<br/>      values   = list(string)<br/>    })), [])<br/>    managed_policies = optional(list(string), [])<br/>    inline_policies  = optional(map(string), {})<br/>  }))</pre> | `{}` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_role_arns"></a> [role\_arns](#output\_role\_arns) | Map of role name to ARN |
| <a name="output_role_names"></a> [role\_names](#output\_role\_names) | Map of role name to IAM role name |
<!-- END_TF_DOCS -->

## Notes

- The `trust_principals` map currently expects an `aws` key with a list of IAM principal ARNs.
- Managed policies and inline policies are both optional and default to empty.
- Role names are used as the map keys and become the actual IAM role names in AWS.
- Default max session duration is 3600 seconds (1 hour); increase for long-running Terragrunt applies.

## Related ADRs

- ADR-007: Platform IAM Role Model
