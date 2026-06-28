# GitHub OIDC

Creates a GitHub Actions OIDC identity provider (account singleton) and a **map of IAM roles** that GitHub workflows can assume using `aws-actions/configure-aws-credentials`. Each role's trust policy restricts access by GitHub organization, the role's own repositories (OIDC `sub` claim), branch patterns, and event types — so different roles can be scoped to different repos. Supports managed IAM policies and an optional inline policy per role.

## Usage

```hcl
module "github_oidc" {
  source = "../../modules/aws/github_oidc"

  github_org = "centric"

  roles = {
    # One role per repo/team, each scoped to its own repo(s) and permissions.
    "github-actions-ecr-push-alpha" = {
      repos    = ["alpha-shop"]
      branches = ["main"]
      events   = ["pull_request"]
      inline_policy = jsonencode({
        Version   = "2012-10-17"
        Statement = [{ Effect = "Allow", Action = ["ecr:PutImage"], Resource = "arn:aws:ecr:*:*:repository/team-alpha/*" }]
      })
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
module "github_oidc" {
  source = "../../modules/aws/github_oidc"
  create = false

  github_org = "centric"
}
```

### Single Role with Managed Policy

```hcl
module "github_oidc" {
  source = "../../modules/aws/github_oidc"

  github_org = "centric"

  roles = {
    "github-actions-terratest" = {
      repos                = ["platform"]
      branches             = ["main", "refs/heads/feat/*"]
      role_policy_arns     = ["arn:aws:iam::aws:policy/AdministratorAccess"]
      max_session_duration = 3600
    }
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
| [aws_iam_openid_connect_provider.github](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_openid_connect_provider) | resource |
| [aws_iam_role.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.inline](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.managed](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_policy_document.trust](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_github_org"></a> [github\_org](#input\_github\_org) | GitHub organization name | `string` | n/a | yes |
| <a name="input_create"></a> [create](#input\_create) | Whether to create the OIDC provider and roles | `bool` | `true` | no |
| <a name="input_roles"></a> [roles](#input\_roles) | Map of IAM role name to its GitHub Actions OIDC configuration. Each role trusts<br/>only the listed repos (scoped via the OIDC `sub` claim) for the given branches<br/>and events, and carries the given managed/inline policies. | <pre>map(object({<br/>    repos                = list(string)<br/>    branches             = optional(list(string), ["main"])<br/>    events               = optional(list(string), [])<br/>    role_policy_arns     = optional(list(string), [])<br/>    inline_policy        = optional(string)<br/>    max_session_duration = optional(number, 3600)<br/>    tags                 = optional(map(string), {}) # merged onto var.tags (e.g. { Team = "alpha" })<br/>  }))</pre> | `{}` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_oidc_provider_arn"></a> [oidc\_provider\_arn](#output\_oidc\_provider\_arn) | ARN of the GitHub OIDC identity provider |
| <a name="output_role_arns"></a> [role\_arns](#output\_role\_arns) | Map of role name to IAM role ARN |
| <a name="output_role_names"></a> [role\_names](#output\_role\_names) | Map of role name to IAM role name |
<!-- END_TF_DOCS -->

## Notes

- The OIDC thumbprint is set to all `f`s, which is the recommended approach for GitHub Actions since AWS validates the certificate chain rather than a pinned thumbprint.
- One OIDC provider is created per account (singleton); each entry in `roles` becomes a separate IAM role scoped to its own `repos`. Map key = IAM role name.
- Branch patterns that do not start with `refs/` are automatically prefixed with `refs/heads/`.
- Event-based claims (e.g., `pull_request`) are combined with branch-based claims in each role's trust policy using `StringLike`.

## Related ADRs

- ADR-036: GitHub Actions OIDC Federation for CI/CD
