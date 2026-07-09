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

  pull_account_ids = ["<PREPROD_ACCOUNT_ID>", "<PROD_ACCOUNT_ID>"]
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
| [aws_ecr_lifecycle_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_lifecycle_policy) | resource |
| [aws_ecr_pull_through_cache_rule.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_pull_through_cache_rule) | resource |
| [aws_ecr_repository.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_repository) | resource |
| [aws_ecr_repository_policy.cross_account_pull](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_repository_policy) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_create"></a> [create](#input\_create) | Whether to create ECR repositories | `bool` | `true` | no |
| <a name="input_force_delete"></a> [force\_delete](#input\_force\_delete) | Whether to allow deletion of non-empty repositories | `bool` | `false` | no |
| <a name="input_max_image_count"></a> [max\_image\_count](#input\_max\_image\_count) | Maximum number of tagged images to retain per repository | `number` | `50` | no |
| <a name="input_pull_account_ids"></a> [pull\_account\_ids](#input\_pull\_account\_ids) | AWS account IDs allowed to pull images cross-account | `list(string)` | `[]` | no |
| <a name="input_pull_through_cache_rules"></a> [pull\_through\_cache\_rules](#input\_pull\_through\_cache\_rules) | ECR pull-through cache rules that lazily mirror public registries into this account. Keys are the local repository prefix (e.g. 'docker-hub'); a first pull of `<acct>.dkr.ecr.<region>.amazonaws.com/<prefix>/<image>` caches the upstream image. credential\_arn (optional) is a Secrets Manager secret ARN — its name MUST start with `ecr-pullthroughcache/` — required for authenticated upstreams like Docker Hub; anonymous upstreams (ghcr.io, quay.io, registry.k8s.io) omit it. | <pre>map(object({<br/>    upstream_registry_url = string<br/>    credential_arn        = optional(string)<br/>  }))</pre> | `{}` | no |
| <a name="input_repositories"></a> [repositories](#input\_repositories) | Map of repository names to configuration. Keys are repo names (e.g. 'team-alpha/app'). Set tag\_mutability = IMMUTABLE\_WITH\_EXCLUSION to keep image tags immutable while exempting cosign's sha256-* tags (see tag\_mutability\_exclusion\_filters). | <pre>map(object({<br/>    tag_mutability = optional(string, "IMMUTABLE")<br/>    tags           = optional(map(string), {}) # merged onto var.tags (e.g. { Team = "alpha" })<br/>  }))</pre> | `{}` | no |
| <a name="input_tag_mutability_exclusion_filters"></a> [tag\_mutability\_exclusion\_filters](#input\_tag\_mutability\_exclusion\_filters) | WILDCARD tag patterns exempted from immutability for repos using tag\_mutability = IMMUTABLE\_WITH\_EXCLUSION. Default exempts cosign's `sha256-*` signature/attestation tags so they can be updated (needed to hold multiple attestations — SBOM + provenance) while image tags stay immutable. | `list(string)` | <pre>[<br/>  "sha256-*"<br/>]</pre> | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_pull_through_cache_prefixes"></a> [pull\_through\_cache\_prefixes](#output\_pull\_through\_cache\_prefixes) | Map of pull-through cache rule keys to their ECR repository prefix |
| <a name="output_repository_arns"></a> [repository\_arns](#output\_repository\_arns) | Map of repository names to their ARNs |
| <a name="output_repository_urls"></a> [repository\_urls](#output\_repository\_urls) | Map of repository names to their URLs |
<!-- END_TF_DOCS -->

## Notes

- Repository names follow the `team-<team>/<product>-<svc>` convention (Team→Product→Service, ADR-067/072).
- Image tag immutability defaults to `IMMUTABLE`; override per repository by setting `tag_mutability = "MUTABLE"` in the repository map value.
- Cross-account pull policies are applied only when `pull_account_ids` is non-empty.
- Set `force_delete = true` to allow deletion of repositories that still contain images (useful for teardowns).
- **Pull-through cache** (`pull_through_cache_rules`) mirrors public registries into this account on first pull (ADR-098 D2). Only `registry.k8s.io` supports anonymous pull-through; Docker Hub, `ghcr.io`, and `quay.io` each **require** a Secrets Manager credential whose name starts with `ecr-pullthroughcache/` (AWS rejects the rule otherwise). The pulling principal needs `ecr:BatchImportUpstreamImage` + `ecr:CreateRepository`.

## Related ADRs

- ADR-028: ECR Cross-Account Container Registry
- ADR-098: Package Registry — AWS CodeArtifact (+ ECR Pull-Through Cache)
