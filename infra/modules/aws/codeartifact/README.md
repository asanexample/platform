# CodeArtifact

Creates an AWS CodeArtifact **domain** (the dedupe + KMS-encryption boundary) with two kinds of repositories:

- **Store repositories** — each carries a single **external connection** that proxies and caches one public
  source (`public:npmjs`, `public:pypi`, `public:maven-central`, `public:nuget-org`, …). A CodeArtifact
  repository may have at most one external connection, so each format gets its own store repo.
- **Consumer repositories** — typically per-Team/Product, listing store repos (or each other) as **upstreams**.
  A package not found locally is fetched from an upstream's external connection and cached in the domain.

Cross-account **read** (pull) access is granted by a domain permissions policy (auth-token + endpoint
resolution) plus a per-consumer-repository permissions policy (the standard read action set), and the domain's
KMS key policy grants `Decrypt` to the same accounts. This mirrors the ECR module's centralized-registry,
cross-account-pull topology (ADR-028) — CodeArtifact is the language-package sibling (ADR-098).

This is the language-package counterpart to the [`ecr`](../ecr) module (OCI images). Auth is IAM/Pod-Identity
(runtime) + GitHub OIDC (CI); there are no local users. **Go modules are not a CodeArtifact package format**
(ADR-098 D5) — handle Go dependency caching out of band (Athens or direct `GOPROXY`).

## Usage

```hcl
module "codeartifact" {
  source = "../../modules/aws/codeartifact"

  domain_name = "refplat"

  # One store repo per public source (single external connection each).
  store_repositories = {
    "npm-store"   = { external_connection = "public:npmjs" }
    "pypi-store"  = { external_connection = "public:pypi" }
    "maven-store" = { external_connection = "public:maven-central" }
    "nuget-store" = { external_connection = "public:nuget-org" }
  }

  # Per-Product consumer repos pull public deps through the store repos and hold private packages.
  repositories = {
    "alpha-shop" = {
      description = "team alpha / shop packages"
      upstreams   = ["npm-store", "pypi-store"]
      tags        = { Team = "alpha", Product = "shop" }
    }
  }

  # Preprod + prod may read (pull) cross-account.
  read_account_ids = ["<PREPROD_ACCOUNT_ID>", "<PROD_ACCOUNT_ID>"]

  tags = {
    Environment = "platform"
    ManagedBy   = "opentofu"
  }
}
```

## Examples

### Disabled Module

```hcl
module "codeartifact" {
  source      = "../../modules/aws/codeartifact"
  domain_name = "refplat"
  create      = false
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
| [aws_codeartifact_domain.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/codeartifact_domain) | resource |
| [aws_codeartifact_domain_permissions_policy.cross_account](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/codeartifact_domain_permissions_policy) | resource |
| [aws_codeartifact_repository.store](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/codeartifact_repository) | resource |
| [aws_codeartifact_repository.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/codeartifact_repository) | resource |
| [aws_codeartifact_repository_permissions_policy.cross_account_read](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/codeartifact_repository_permissions_policy) | resource |
| [aws_kms_alias.domain](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.domain](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_domain_name"></a> [domain\_name](#input\_domain\_name) | CodeArtifact domain name — the dedupe + encryption boundary that all repositories live within (e.g. 'refplat') | `string` | n/a | yes |
| <a name="input_create"></a> [create](#input\_create) | Whether to create the CodeArtifact domain and repositories | `bool` | `true` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | KMS key ARN for domain asset encryption. Empty string creates a customer-managed CMK in this module (with rotation). Provide an ARN to use an existing key. | `string` | `""` | no |
| <a name="input_read_account_ids"></a> [read\_account\_ids](#input\_read\_account\_ids) | AWS account IDs granted cross-account read (pull) access to the domain + consumer repositories (e.g. preprod, prod). Empty disables cross-account policies. | `list(string)` | `[]` | no |
| <a name="input_repositories"></a> [repositories](#input\_repositories) | Consumer repositories (typically per-Team/Product). Each may list store/other repositories in this domain as upstreams; a package not found locally is fetched (and cached) from an upstream's external connection. Keys are repository names (e.g. 'alpha-shop'). | <pre>map(object({<br/>    description = optional(string)<br/>    upstreams   = optional(list(string), [])<br/>    tags        = optional(map(string), {})<br/>  }))</pre> | `{}` | no |
| <a name="input_store_repositories"></a> [store\_repositories](#input\_store\_repositories) | Upstream 'store' repositories, each with a single external connection that proxies + caches one public source (e.g. { npm-store = { external\_connection = "public:npmjs" } }). A CodeArtifact repository may have at most ONE external connection, so proxy each format via its own store repo and reference them as upstreams from consumer repositories. | <pre>map(object({<br/>    external_connection = string<br/>    description         = optional(string)<br/>    tags                = optional(map(string), {})<br/>  }))</pre> | `{}` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_domain_arn"></a> [domain\_arn](#output\_domain\_arn) | CodeArtifact domain ARN |
| <a name="output_domain_name"></a> [domain\_name](#output\_domain\_name) | CodeArtifact domain name |
| <a name="output_domain_owner"></a> [domain\_owner](#output\_domain\_owner) | AWS account ID that owns the domain (needed by consumers to construct repository endpoints) |
| <a name="output_kms_key_arn"></a> [kms\_key\_arn](#output\_kms\_key\_arn) | KMS key ARN encrypting the domain's assets |
| <a name="output_repository_arns"></a> [repository\_arns](#output\_repository\_arns) | Map of consumer repository names to their ARNs |
| <a name="output_store_repository_names"></a> [store\_repository\_names](#output\_store\_repository\_names) | Map of store (upstream-proxy) repository names to their names |
<!-- END_TF_DOCS -->

## Notes

- **One external connection per repository** is an AWS limit — proxy each public format via its own store repo,
  then reference those as `upstreams` from consumer repositories.
- Consumer repository names follow the Team→Product convention (ADR-067/069); the live unit derives them from
  the Product registry rather than hand-listing them.
- Cross-account read policies (domain + per-repo + KMS decrypt) are applied only when `read_account_ids` is
  non-empty. Add a new account to that list when onboarding one, same as ECR's `pull_account_ids`.
- The module creates a customer-managed KMS key with rotation by default; pass `kms_key_arn` to reuse a key.
- **Go is not a supported format** — see ADR-098 D5.

## Related ADRs

- ADR-098: Package Registry — AWS CodeArtifact (+ ECR Pull-Through Cache)
- ADR-028: ECR Cross-Account Container Registry (the OCI sibling)
