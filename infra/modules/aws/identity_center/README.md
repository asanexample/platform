# Identity Center

Manages AWS IAM Identity Center (SSO) resources: permission sets (with managed-policy attachments and/or an inline policy), groups, users, group memberships, and account assignments. Users are added to groups, and groups are assigned to accounts with a permission set — a complete SSO configuration for multi-account access.

The four inputs reference each other by name: a `users` entry's `groups` and an `account_assignments` entry's `group` must exist in `groups`, and an assignment's `permission_set` must exist in `permission_sets`.

## Usage

A complete example that exercises every feature, modeled on the platform's per-team developer access (ADR-039): a full-admin set, a per-team developer set that pairs a managed read-only policy with an inline assume-role policy, groups, users added to those groups, and account assignments.

```hcl
module "identity_center" {
  source = "../../modules/aws/identity_center"

  # Permission sets — attach managed policies and/or one inline policy per set.
  permission_sets = {
    AdministratorAccess = {
      description      = "Full administrator access"
      session_duration = "PT4H"
      managed_policies = ["arn:aws:iam::aws:policy/AdministratorAccess"]
    }

    # Per-team developer set: account-wide read PLUS the ability to assume only
    # that team's DeveloperAccess role (the launchpad into namespace-scoped kubectl).
    "Dev-alpha" = {
      description      = "Developer access for team alpha"
      session_duration = "PT4H"
      managed_policies = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
      inline_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [{
          Sid      = "AssumeTeamDeveloperRole"
          Effect   = "Allow"
          Action   = "sts:AssumeRole"
          Resource = "arn:aws:iam::<PREPROD_ACCOUNT_ID>:role/DeveloperAccess-alpha"
        }]
      })
    }
  }

  # Groups — account assignments target groups, never individual users.
  groups = {
    "Admins"           = { description = "Platform administrators" }
    "Developers-alpha" = { description = "Developers for team alpha" }
  }

  # Users — created in the Identity Store and added to groups by name.
  users = {
    "josh" = {
      given_name  = "Josh"
      family_name = "Deeden"
      email       = "josh@example.com"
      groups      = ["Admins"]
    }
    "alpha-dev" = {
      given_name  = "Alpha"
      family_name = "Developer"
      email       = "alpha-dev@example.com"
      groups      = ["Developers-alpha"]
    }
  }

  # Account assignments — (group, account, permission set). Creating an
  # assignment also provisions the permission set into the target account.
  account_assignments = [
    { account_id = "<MGMT_ACCOUNT_ID>", permission_set = "AdministratorAccess", group = "Admins" },
    { account_id = "<PREPROD_ACCOUNT_ID>", permission_set = "Dev-alpha", group = "Developers-alpha" },
  ]

  tags = {
    ManagedBy = "opentofu"
  }
}
```

> Note: object keys containing hyphens (e.g. `"Dev-alpha"`, `"Developers-alpha"`) must be quoted.

## Examples

### Disabled Module

```hcl
module "identity_center" {
  source = "../../modules/aws/identity_center"
  create = false
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
- Account assignments link groups (not individual users) to accounts with permission sets. Assigning a permission set to a group on an account also provisions that permission set into the account — there is no separate provisioning step.
- Each permission set supports at most one inline policy (`inline_policy`); combine it with `managed_policies` for additional grants.
- **Identity source:** this module manages users and groups as Terraform resources (`aws_identitystore_user` / `aws_identitystore_group`), which requires IAM Identity Center to be the **identity source**. If you sync from an external IdP via SCIM (Okta, Entra ID, etc.), manage users and groups in that IdP instead and use only `permission_sets` + `account_assignments` here (assignments reference the SCIM-provisioned group by name).

## Related ADRs

- ADR-007: Platform IAM Role Model
- ADR-039: Per-Team Developer RBAC (uses per-team `Dev-<team>` permission sets and `Developers-<team>` groups)
