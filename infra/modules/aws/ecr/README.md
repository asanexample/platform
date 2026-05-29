# ECR

Creates Amazon Elastic Container Registry (ECR) repositories with scan-on-push enabled, AES256 encryption, and lifecycle policies. Lifecycle rules expire untagged images after 7 days and retain up to a configurable number of tagged images. Supports cross-account pull access by attaching repository policies that grant `ecr:BatchGetImage`, `ecr:GetDownloadUrlForLayer`, and `ecr:BatchCheckLayerAvailability` to specified AWS account IDs.

## Usage

```hcl
module "ecr" {
  source = "../../modules/aws/ecr"

  repositories = {
    "team-alpha/web-app"  = {}
    "team-alpha/api"      = {}
    "team-bravo/frontend" = { tag_mutability = "MUTABLE" }
  }

  pull_account_ids = ["620830101009", "554518885123"]
  max_image_count  = 50

  tags = {
    Environment = "platform"
    ManagedBy   = "opentofu"
  }
}
```

## Examples

### Disabled Module

```hcl
module "ecr" {
  source = "../../modules/aws/ecr"
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
| [aws_ecr_lifecycle_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_lifecycle_policy) | resource |
| [aws_ecr_repository.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_repository) | resource |
| [aws_ecr_repository_policy.cross_account_pull](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_repository_policy) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_create"></a> [create](#input\_create) | Whether to create ECR repositories | `bool` | `true` | no |
| <a name="input_force_delete"></a> [force\_delete](#input\_force\_delete) | Whether to allow deletion of non-empty repositories | `bool` | `false` | no |
| <a name="input_max_image_count"></a> [max\_image\_count](#input\_max\_image\_count) | Maximum number of tagged images to retain per repository | `number` | `50` | no |
| <a name="input_pull_account_ids"></a> [pull\_account\_ids](#input\_pull\_account\_ids) | AWS account IDs allowed to pull images cross-account | `list(string)` | `[]` | no |
| <a name="input_repositories"></a> [repositories](#input\_repositories) | Map of repository names to configuration. Keys are repo names (e.g. 'team-alpha/app'). | `map(map(string))` | `{}` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_repository_arns"></a> [repository\_arns](#output\_repository\_arns) | Map of repository names to their ARNs |
| <a name="output_repository_urls"></a> [repository\_urls](#output\_repository\_urls) | Map of repository names to their URLs |
<!-- END_TF_DOCS -->

## Notes

- Repository names follow the `team-<team>/<app>` convention established by the multi-app tenant model.
- Image tag immutability defaults to `IMMUTABLE`; override per repository by setting `tag_mutability = "MUTABLE"` in the repository map value.
- Cross-account pull policies are applied only when `pull_account_ids` is non-empty.
- Set `force_delete = true` to allow deletion of repositories that still contain images (useful for teardowns).

## Related ADRs

- ADR-028: ECR Cross-Account Container Registry
