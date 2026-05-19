# GitHub OIDC

Creates a GitHub Actions OIDC identity provider and IAM role for CI/CD workflows with branch-scoped trust policies.

## Usage

```hcl
module "github_oidc" {
  source = "../../modules/aws/github_oidc"

  create = true

  # Required
  github_org  = "my-org"
  github_repo = "my-repo"
  role_name   = "github-actions-deploy"

  # Optional
  github_branches      = ["main", "refs/heads/release/*"]
  role_policy_arns     = ["arn:aws:iam::aws:policy/AdministratorAccess"]
  inline_policy        = ""
  max_session_duration = 3600

  tags = {
    Environment = "platform"
    ManagedBy   = "Terragrunt"
  }
}
```

## Examples

### Disabled module

```hcl
module "github_oidc" {
  source = "../../modules/aws/github_oidc"
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
| [aws_iam_openid_connect_provider.github](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_openid_connect_provider) | resource |
| [aws_iam_role.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.inline](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.managed](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.trust](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_create"></a> [create](#input\_create) | Whether to create the OIDC provider and role | `bool` | `true` | no |
| <a name="input_github_branches"></a> [github\_branches](#input\_github\_branches) | List of branch patterns allowed to assume the role (e.g. ["main", "refs/heads/feat/*"]) | `list(string)` | <pre>[<br/>  "main"<br/>]</pre> | no |
| <a name="input_github_org"></a> [github\_org](#input\_github\_org) | GitHub organization name | `string` | n/a | yes |
| <a name="input_github_repo"></a> [github\_repo](#input\_github\_repo) | GitHub repository name | `string` | n/a | yes |
| <a name="input_inline_policy"></a> [inline\_policy](#input\_inline\_policy) | Optional inline IAM policy JSON to attach to the role | `string` | `""` | no |
| <a name="input_max_session_duration"></a> [max\_session\_duration](#input\_max\_session\_duration) | Maximum session duration in seconds for the role | `number` | `3600` | no |
| <a name="input_role_name"></a> [role\_name](#input\_role\_name) | Name of the IAM role to create | `string` | n/a | yes |
| <a name="input_role_policy_arns"></a> [role\_policy\_arns](#input\_role\_policy\_arns) | List of managed IAM policy ARNs to attach to the role | `list(string)` | `[]` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_oidc_provider_arn"></a> [oidc\_provider\_arn](#output\_oidc\_provider\_arn) | ARN of the GitHub OIDC identity provider |
| <a name="output_role_arn"></a> [role\_arn](#output\_role\_arn) | ARN of the IAM role for GitHub Actions |
| <a name="output_role_name"></a> [role\_name](#output\_role\_name) | Name of the IAM role |
<!-- END_TF_DOCS -->

## Dependencies

None.
