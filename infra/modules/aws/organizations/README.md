# Organizations

Manages an AWS Organization with organizational units, accounts, and Service Control Policies (SCPs). Includes seven built-in SCPs covering baseline guardrails, security service protection, encryption enforcement, region restriction, data/network protection, tagging requirements, and IAM user restrictions, plus an optional HIPAA eligible services allowlist. All built-in SCPs can be overridden with custom policies via `service_control_policies`. SCP attachments are configurable per OU or organization root.

## Usage

```hcl
module "organizations" {
  source = "../../modules/aws/organizations"

  create_organization = false

  organizational_units = {
    Platform  = { parent = null }
    Workloads = { parent = null }
    "Workloads/PreProd" = { parent = "Workloads" }
    "Workloads/Prod"    = { parent = "Workloads" }
  }

  accounts = {
    platform = {
      email = "platform@example.com"
      ou    = "Platform"
    }
    preprod = {
      email = "preprod@example.com"
      ou    = "Workloads/PreProd"
    }
  }

  allowed_regions = ["us-east-1", "us-west-2"]
  required_tags   = ["Environment", "ManagedBy", "Owner"]
  exempt_roles    = ["OrganizationAccountAccessRole", "PlatformDeployer"]

  scp_attachments = {
    "root"      = ["baseline-guardrails", "protect-security-services", "enforce-encryption", "deny-regions"]
    "Platform"  = ["protect-data-and-network"]
    "Workloads" = ["protect-data-and-network", "require-tagging", "restrict-iam-users"]
  }

  tags = {
    ManagedBy = "opentofu"
  }
}
```

## Examples

### Disabled Module

```hcl
module "organizations" {
  source = "../../modules/aws/organizations"
  create = false
}
```

### With HIPAA SCP

```hcl
module "organizations" {
  source = "../../modules/aws/organizations"

  create_organization = false
  enable_hipaa_scp    = true

  scp_attachments = {
    "root"      = ["baseline-guardrails", "enforce-encryption", "deny-regions"]
    "Workloads" = ["hipaa-eligible-services"]
  }

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
| [aws_organizations_account.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_account) | resource |
| [aws_organizations_organization.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_organization) | resource |
| [aws_organizations_organizational_unit.child](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_organizational_unit) | resource |
| [aws_organizations_organizational_unit.top_level](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_organizational_unit) | resource |
| [aws_organizations_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_policy) | resource |
| [aws_organizations_policy_attachment.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_policy_attachment) | resource |
| [aws_iam_policy_document.baseline_guardrails](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.deny_regions](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.enforce_encryption](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.hipaa_eligible_services](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.protect_data_and_network](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.protect_security_services](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.require_tagging](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.restrict_iam_users](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_organizations_organization.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/organizations_organization) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_accounts"></a> [accounts](#input\_accounts) | Map of account names to their configuration. | <pre>map(object({<br/>    email = string<br/>    ou    = optional(string)<br/>  }))</pre> | `{}` | no |
| <a name="input_allowed_regions"></a> [allowed\_regions](#input\_allowed\_regions) | AWS regions where resources are allowed (used by region-deny SCP). | `list(string)` | <pre>[<br/>  "us-east-1",<br/>  "us-west-2"<br/>]</pre> | no |
| <a name="input_create"></a> [create](#input\_create) | Whether to create any resources in this module. | `bool` | `true` | no |
| <a name="input_create_organization"></a> [create\_organization](#input\_create\_organization) | Whether to create the AWS Organization (false to data-source an existing one). | `bool` | `false` | no |
| <a name="input_enable_hipaa_scp"></a> [enable\_hipaa\_scp](#input\_enable\_hipaa\_scp) | Whether to enable the HIPAA eligible services allowlist SCP. | `bool` | `false` | no |
| <a name="input_exempt_roles"></a> [exempt\_roles](#input\_exempt\_roles) | IAM role names exempt from SCP deny statements. | `list(string)` | <pre>[<br/>  "OrganizationAccountAccessRole"<br/>]</pre> | no |
| <a name="input_organization_aws_service_access_principals"></a> [organization\_aws\_service\_access\_principals](#input\_organization\_aws\_service\_access\_principals) | AWS service principals to enable for organization integration. | `list(string)` | <pre>[<br/>  "cloudtrail.amazonaws.com",<br/>  "config.amazonaws.com",<br/>  "guardduty.amazonaws.com",<br/>  "securityhub.amazonaws.com",<br/>  "access-analyzer.amazonaws.com",<br/>  "sso.amazonaws.com",<br/>  "tagpolicies.tag.amazonaws.com"<br/>]</pre> | no |
| <a name="input_organization_enabled_policy_types"></a> [organization\_enabled\_policy\_types](#input\_organization\_enabled\_policy\_types) | Policy types to enable in the organization. | `list(string)` | <pre>[<br/>  "SERVICE_CONTROL_POLICY",<br/>  "TAG_POLICY"<br/>]</pre> | no |
| <a name="input_organizational_units"></a> [organizational\_units](#input\_organizational\_units) | Map of OU names to their configuration. Key is the OU name, parent=null for root-level OUs. | <pre>map(object({<br/>    parent = optional(string)<br/>  }))</pre> | `{}` | no |
| <a name="input_required_tags"></a> [required\_tags](#input\_required\_tags) | Tag keys that must be present on supported resources. | `list(string)` | <pre>[<br/>  "Environment",<br/>  "ManagedBy",<br/>  "Owner"<br/>]</pre> | no |
| <a name="input_scp_attachments"></a> [scp\_attachments](#input\_scp\_attachments) | Map of target name to list of SCP names to attach. Use 'root' for the org root. | `map(list(string))` | <pre>{<br/>  "Platform": [<br/>    "protect-data-and-network"<br/>  ],<br/>  "Workloads": [<br/>    "protect-data-and-network",<br/>    "require-tagging",<br/>    "restrict-iam-users"<br/>  ],<br/>  "root": [<br/>    "baseline-guardrails",<br/>    "protect-security-services",<br/>    "enforce-encryption",<br/>    "deny-regions"<br/>  ]<br/>}</pre> | no |
| <a name="input_service_control_policies"></a> [service\_control\_policies](#input\_service\_control\_policies) | Custom SCP JSON map override. When set, replaces all built-in default SCPs. | `map(string)` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to SCPs and OUs. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_account_arns"></a> [account\_arns](#output\_account\_arns) | Map of account names to their ARNs. |
| <a name="output_account_ids"></a> [account\_ids](#output\_account\_ids) | Map of account names to their IDs. |
| <a name="output_organization_arn"></a> [organization\_arn](#output\_organization\_arn) | The ARN of the AWS Organization. |
| <a name="output_organization_id"></a> [organization\_id](#output\_organization\_id) | The ID of the AWS Organization. |
| <a name="output_ou_arns"></a> [ou\_arns](#output\_ou\_arns) | Map of OU names to their ARNs. |
| <a name="output_ou_ids"></a> [ou\_ids](#output\_ou\_ids) | Map of OU names to their IDs. |
| <a name="output_root_id"></a> [root\_id](#output\_root\_id) | The ID of the organization root. |
| <a name="output_scp_ids"></a> [scp\_ids](#output\_scp\_ids) | Map of SCP names to their IDs. |
<!-- END_TF_DOCS -->

## Notes

- Organization, OUs, and accounts have `prevent_destroy` lifecycle rules to avoid accidental deletion.
- Set `create_organization = false` (the default) to use a data source for an existing organization rather than creating a new one.
- Built-in SCPs exempt roles listed in `exempt_roles` from deny statements using `ArnNotLike` conditions. The default exemption is `OrganizationAccountAccessRole`.
- The `service_control_policies` variable replaces all built-in SCPs when set. Use it only if you need complete control over SCP content.
- Child OUs use slash-separated keys (e.g., `Workloads/PreProd`) where the `parent` field references the top-level OU key.
