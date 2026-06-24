# External Secrets Operator

Deploys the External Secrets Operator (ESO) via Helm for reading secrets from AWS Secrets Manager and SSM Parameter Store, with AWS identity via **EKS Pod Identity** (ADR-047). Creates an IAM role scoped to configurable path prefixes for both Secrets Manager and SSM (with optional KMS decrypt), and a Pod Identity association binding it to the `external-secrets` controller ServiceAccount. The module installs CRDs automatically. ClusterSecretStore resources are created separately via the `secret-stores` module — they authenticate as this controller identity (no per-store `serviceAccountRef`).

## Usage

```hcl
module "external_secrets" {
  source = "../../modules/external-secrets"

  cluster_name   = "platform-use1-eks"
  aws_account_id = "<PLATFORM_ACCOUNT_ID>"

  secret_path_prefix = "platform"
  ssm_path_prefix    = "/platform"
  kms_key_arns       = ["arn:aws:kms:us-east-1:<PLATFORM_ACCOUNT_ID>:key/example-key-id"]

  tags = {
    Environment = "platform"
    ManagedBy   = "terraform"
  }
}
```

## Examples

### Disabled Module

```hcl
module "external_secrets" {
  source = "../../modules/external-secrets"

  create         = false
  cluster_name   = "platform-use1-eks"
  aws_account_id = "<PLATFORM_ACCOUNT_ID>"
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | >= 3.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 5.0 |
| <a name="provider_helm"></a> [helm](#provider\_helm) | >= 3.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_eks_pod_identity_association.external_secrets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_pod_identity_association) | resource |
| [aws_iam_role.external_secrets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.external_secrets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [helm_release.external_secrets](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [aws_iam_policy_document.external_secrets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.external_secrets_trust](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_aws_account_id"></a> [aws\_account\_id](#input\_aws\_account\_id) | AWS account ID for scoping IAM policy resources | `string` | n/a | yes |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the EKS cluster (used for IAM role naming) | `string` | n/a | yes |
| <a name="input_create"></a> [create](#input\_create) | Controls whether resources should be created | `bool` | `true` | no |
| <a name="input_helm_chart"></a> [helm\_chart](#input\_helm\_chart) | Name of the Helm chart | `string` | `"external-secrets"` | no |
| <a name="input_helm_chart_version"></a> [helm\_chart\_version](#input\_helm\_chart\_version) | Version of the external-secrets Helm chart | `string` | `"0.14.3"` | no |
| <a name="input_helm_release_name"></a> [helm\_release\_name](#input\_helm\_release\_name) | Name of the Helm release | `string` | `"external-secrets"` | no |
| <a name="input_helm_repository"></a> [helm\_repository](#input\_helm\_repository) | Repository URL for the external-secrets Helm chart | `string` | `"https://charts.external-secrets.io"` | no |
| <a name="input_helm_timeout"></a> [helm\_timeout](#input\_helm\_timeout) | Timeout for Helm operations in seconds | `number` | `600` | no |
| <a name="input_helm_wait"></a> [helm\_wait](#input\_helm\_wait) | Whether to wait for Helm release to complete | `bool` | `true` | no |
| <a name="input_kms_key_arns"></a> [kms\_key\_arns](#input\_kms\_key\_arns) | KMS key ARNs that external-secrets is allowed to decrypt | `list(string)` | `[]` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Kubernetes namespace to install external-secrets into | `string` | `"external-secrets"` | no |
| <a name="input_secret_path_prefix"></a> [secret\_path\_prefix](#input\_secret\_path\_prefix) | Secrets Manager path prefix for scoping access (e.g., 'platform') | `string` | `"*"` | no |
| <a name="input_ssm_path_prefix"></a> [ssm\_path\_prefix](#input\_ssm\_path\_prefix) | SSM Parameter Store path prefix for scoping access (e.g., '/platform') | `string` | `"/*"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_helm_release_status"></a> [helm\_release\_status](#output\_helm\_release\_status) | Status of the external-secrets Helm release |
| <a name="output_role_arn"></a> [role\_arn](#output\_role\_arn) | ARN of the external-secrets IAM role (bound to the controller SA via EKS Pod Identity) |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Kubernetes namespace where external-secrets is installed |
<!-- END_TF_DOCS -->

## Notes

- The IAM policy scopes Secrets Manager access to `arn:aws:secretsmanager:*:<account>:secret:<prefix>/*` and SSM to `arn:aws:ssm:*:<account>:parameter<prefix>/*`. Use `secret_path_prefix = "*"` and `ssm_path_prefix = "/*"` for unrestricted access (the defaults).
- KMS decrypt permissions are only included when `kms_key_arns` is non-empty. This is needed when secrets are encrypted with a customer-managed KMS key.
- This module only installs the ESO operator. ClusterSecretStore resources that configure which backend to use are managed by the `secret-stores` module.

## Related ADRs

- ADR-019: External Secrets Operator for Secrets Management
- ADR-047: EKS Pod Identity as the Standard for Pod AWS Identity
