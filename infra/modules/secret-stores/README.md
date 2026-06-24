# Secret Stores

Creates ClusterSecretStore resources for the External Secrets Operator (ESO), configuring AWS Secrets Manager and optionally AWS SSM Parameter Store as secret backends. Authentication uses **EKS Pod Identity** (ADR-047): the stores carry no per-store credentials — ESO authenticates as its controller pod's own identity (the `external-secrets` SA bound to its IAM role). These resources are cluster-scoped, so any namespace can reference them in ExternalSecret manifests.

## Usage

```hcl
module "secret_stores" {
  source = "../../modules/secret-stores"

  region                    = "us-east-1"
  store_name       = "aws-secrets-manager"
  create_ssm_store = true
}
```

## Examples

### Disabled Module

```hcl
module "secret_stores" {
  source = "../../modules/secret-stores"

  create = false
  region = "us-east-1"
}
```

### Secrets Manager Only (No SSM)

```hcl
module "secret_stores" {
  source = "../../modules/secret-stores"

  region           = "us-east-1"
  create_ssm_store = false
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | >= 2.35.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | >= 2.35.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [kubernetes_manifest.cluster_secret_store](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_manifest.cluster_secret_store_ssm](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_region"></a> [region](#input\_region) | AWS region for the secret store backend | `string` | n/a | yes |
| <a name="input_create"></a> [create](#input\_create) | Controls whether resources should be created | `bool` | `true` | no |
| <a name="input_create_ssm_store"></a> [create\_ssm\_store](#input\_create\_ssm\_store) | Also create a ClusterSecretStore for SSM Parameter Store | `bool` | `true` | no |
| <a name="input_store_name"></a> [store\_name](#input\_store\_name) | Name of the ClusterSecretStore resource | `string` | `"aws-secrets-manager"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_cluster_secret_store_name"></a> [cluster\_secret\_store\_name](#output\_cluster\_secret\_store\_name) | Name of the Secrets Manager ClusterSecretStore |
| <a name="output_cluster_secret_store_ssm_name"></a> [cluster\_secret\_store\_ssm\_name](#output\_cluster\_secret\_store\_ssm\_name) | Name of the SSM Parameter Store ClusterSecretStore |
<!-- END_TF_DOCS -->

## Notes

- This module only creates ClusterSecretStore resources. The ESO operator itself must be deployed first (via the `external-secrets` module); its controller SA holds the Secrets Manager / SSM permissions via EKS Pod Identity.
- When `create_ssm_store = true` (default), a second ClusterSecretStore named `<store_name>-ssm` is created for SSM Parameter Store access.

## Related ADRs

- ADR-024: Secrets Management Architecture
- ADR-019: External Secrets Operator for Secrets Management
- ADR-047: EKS Pod Identity as the Standard for Pod AWS Identity
