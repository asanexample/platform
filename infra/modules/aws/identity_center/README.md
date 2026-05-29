# Identity Center

Manages AWS IAM Identity Center (SSO) resources including permission sets, groups, users, group memberships, and account assignments. Permission sets support both managed policy attachments and inline policies. Users are assigned to groups, and groups are assigned to accounts with specific permission sets, creating a complete SSO configuration for multi-account access.

## Usage

```hcl
module "identity_center" {
  source = "../../modules/aws/identity_center"

  permission_sets = {
    AdministratorAccess = {
      description      = "Full admin access"
      session_duration = "PT4H"
      managed_policies = ["arn:aws:iam::aws:policy/AdministratorAccess"]
    }
    ReadOnlyAccess = {
      description      = "Read-only access"
      managed_policies = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
    }
  }

  groups = {
    PlatformEngineers = { description = "Platform team" }
    Developers        = { description = "Application developers" }
  }

  users = {
    jdeeden = {
      given_name  = "Josh"
      family_name = "Deeden"
      email       = "josh@example.com"
      groups      = ["PlatformEngineers"]
    }
  }

  account_assignments = [
    {
      account_id     = "829808296602"
      permission_set = "AdministratorAccess"
      group          = "PlatformEngineers"
    },
    {
      account_id     = "620830101009"
      permission_set = "ReadOnlyAccess"
      group          = "Developers"
    },
  ]

  tags = {
    ManagedBy = "opentofu"
  }
}
```

## Examples

### Disabled Module

```hcl
module "identity_center" {
  source = "../../modules/aws/identity_center"
  create = false
}
```

### Permission Set with Inline Policy

```hcl
module "identity_center" {
  source = "../../modules/aws/identity_center"

  permission_sets = {
    EKSAdmin = {
      description      = "EKS cluster admin with assume-role"
      session_duration = "PT8H"
      inline_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [{
          Effect   = "Allow"
          Action   = ["sts:AssumeRole"]
          Resource = ["arn:aws:iam::*:role/PlatformAdmin"]
        }]
      })
    }
  }

  groups              = {}
  users               = {}
  account_assignments = []

  tags = {
    ManagedBy = "opentofu"
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
| [aws_identitystore_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/identitystore_group) | resource |
| [aws_identitystore_group_membership.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/identitystore_group_membership) | resource |
| [aws_identitystore_user.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/identitystore_user) | resource |
| [aws_ssoadmin_account_assignment.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssoadmin_account_assignment) | resource |
| [aws_ssoadmin_managed_policy_attachment.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssoadmin_managed_policy_attachment) | resource |
| [aws_ssoadmin_permission_set.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssoadmin_permission_set) | resource |
| [aws_ssoadmin_permission_set_inline_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssoadmin_permission_set_inline_policy) | resource |
| [aws_ssoadmin_instances.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ssoadmin_instances) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_account_assignments"></a> [account\_assignments](#input\_account\_assignments) | List of group-to-account permission set assignments. | <pre>list(object({<br/>    account_id     = string<br/>    permission_set = string<br/>    group          = string<br/>  }))</pre> | `[]` | no |
| <a name="input_create"></a> [create](#input\_create) | Whether to create any resources in this module. | `bool` | `true` | no |
| <a name="input_groups"></a> [groups](#input\_groups) | Map of group names to their configuration. | <pre>map(object({<br/>    description = optional(string, "")<br/>  }))</pre> | `{}` | no |
| <a name="input_permission_sets"></a> [permission\_sets](#input\_permission\_sets) | Map of permission set names to their configuration. | <pre>map(object({<br/>    description      = optional(string, "")<br/>    session_duration = optional(string, "PT4H")<br/>    managed_policies = optional(list(string), [])<br/>    inline_policy    = optional(string)<br/>  }))</pre> | `{}` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to permission sets. | `map(string)` | `{}` | no |
| <a name="input_users"></a> [users](#input\_users) | Map of usernames to their configuration. | <pre>map(object({<br/>    given_name   = string<br/>    family_name  = string<br/>    email        = string<br/>    display_name = optional(string)<br/>    groups       = optional(list(string), [])<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_group_ids"></a> [group\_ids](#output\_group\_ids) | Map of group names to their IDs. |
| <a name="output_identity_store_id"></a> [identity\_store\_id](#output\_identity\_store\_id) | The ID of the Identity Store. |
| <a name="output_instance_arn"></a> [instance\_arn](#output\_instance\_arn) | The ARN of the IAM Identity Center instance. |
| <a name="output_permission_set_arns"></a> [permission\_set\_arns](#output\_permission\_set\_arns) | Map of permission set names to their ARNs. |
| <a name="output_user_ids"></a> [user\_ids](#output\_user\_ids) | Map of usernames to their IDs. |
<!-- END_TF_DOCS -->

## Notes

- The module automatically discovers the IAM Identity Center instance ARN and Identity Store ID using data sources; no manual configuration is needed.
- Must be run in the management account where IAM Identity Center is enabled.
- Permission set session duration uses ISO 8601 duration format (e.g., `PT4H` for 4 hours).
- Account assignments link groups (not individual users) to accounts with permission sets.

## Related ADRs

- ADR-007: Platform IAM Role Model
