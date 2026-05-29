# GitHub OIDC

Creates a GitHub Actions OIDC identity provider and an IAM role that GitHub workflows can assume using `aws-actions/configure-aws-credentials`. The trust policy restricts access by GitHub organization, repository names, branch patterns, and event types. Supports attaching both managed IAM policies and an optional inline policy to the role.

## Usage

```hcl
module "github_oidc" {
  source = "../../modules/aws/github_oidc"

  github_org   = "centric"
  github_repos = ["platform", "app-frontend"]
  role_name    = "github-actions-deploy"

  github_branches = ["main", "refs/heads/release/*"]

  role_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser",
  ]

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
  role_name  = "unused"
}
```

### Single Repo with Inline Policy

```hcl
module "github_oidc" {
  source = "../../modules/aws/github_oidc"

  github_org  = "centric"
  github_repo = "platform"
  role_name   = "github-actions-terratest"

  github_branches = ["main"]
  github_events   = ["pull_request"]

  inline_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["eks:DescribeCluster"]
      Resource = "*"
    }]
  })

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
| [aws_iam_openid_connect_provider.github](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_openid_connect_provider) | resource |
| [aws_iam_role.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.inline](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.managed](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.trust](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_github_org"></a> [github\_org](#input\_github\_org) | GitHub organization name | `string` | n/a | yes |
| <a name="input_role_name"></a> [role\_name](#input\_role\_name) | Name of the IAM role to create | `string` | n/a | yes |
| <a name="input_create"></a> [create](#input\_create) | Whether to create the OIDC provider and role | `bool` | `true` | no |
| <a name="input_github_branches"></a> [github\_branches](#input\_github\_branches) | List of branch patterns allowed to assume the role (e.g. ["main", "refs/heads/feat/*"]) | `list(string)` | <pre>[<br/>  "main"<br/>]</pre> | no |
| <a name="input_github_events"></a> [github\_events](#input\_github\_events) | GitHub event types to allow (e.g. ["pull\_request"]) | `list(string)` | `[]` | no |
| <a name="input_github_repo"></a> [github\_repo](#input\_github\_repo) | GitHub repository name (use github\_repos for multiple) | `string` | `""` | no |
| <a name="input_github_repos"></a> [github\_repos](#input\_github\_repos) | List of GitHub repository names allowed to assume the role | `list(string)` | `[]` | no |
| <a name="input_inline_policy"></a> [inline\_policy](#input\_inline\_policy) | Optional inline IAM policy JSON to attach to the role | `string` | `""` | no |
| <a name="input_max_session_duration"></a> [max\_session\_duration](#input\_max\_session\_duration) | Maximum session duration in seconds for the role | `number` | `3600` | no |
| <a name="input_role_policy_arns"></a> [role\_policy\_arns](#input\_role\_policy\_arns) | List of managed IAM policy ARNs to attach to the role | `list(string)` | `[]` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_oidc_provider_arn"></a> [oidc\_provider\_arn](#output\_oidc\_provider\_arn) | ARN of the GitHub OIDC identity provider |
| <a name="output_role_arn"></a> [role\_arn](#output\_role\_arn) | ARN of the IAM role for GitHub Actions |
| <a name="output_role_name"></a> [role\_name](#output\_role\_name) | Name of the IAM role |
<!-- END_TF_DOCS -->

## Notes

- The OIDC thumbprint is set to all `f`s, which is the recommended approach for GitHub Actions since AWS validates the certificate chain rather than a pinned thumbprint.
- Use `github_repos` (list) for multi-repo access or `github_repo` (string) for a single repo. If both are set, `github_repos` takes precedence.
- Branch patterns that do not start with `refs/` are automatically prefixed with `refs/heads/`.
- Event-based claims (e.g., `pull_request`) are combined with branch-based claims in the trust policy using `StringLike`.

## Related ADRs

- ADR-036: GitHub Actions OIDC Federation for CI/CD
