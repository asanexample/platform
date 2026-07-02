# cnpg-backups

The durable off-cluster home for **CloudNativePG** base backups + continuous WAL archiving (point-in-time
recovery) — one hardened S3 bucket with a **per-cluster key prefix**, plus a **least-privilege IAM role per
cluster** (scoped to its own prefix) bound to the cluster's instance ServiceAccount via **EKS Pod Identity**
(ADR-041/047). The Barman Cloud plugin's `ObjectStore` authenticates with `inheritFromIAMRole`, so these are
the credentials it writes with.

- **Bucket:** TLS-only, full public-access block, versioned, SSE-S3. Lifecycle is hygiene only (abort stale
  multipart uploads, expire old noncurrent versions) — **Barman owns backup retention** via the
  `ObjectStore.retentionPolicy`, not S3.
- **IAM:** one role per cluster, scoped to `s3://<bucket>/<cluster>/*` — a Keycloak-DB backup role can't touch
  the Backstage prefix. Delete is granted because Barman prunes its own old backups/WALs.

Part of #1119 (alerting-blindspot epic #1124): the CNPG clusters (Keycloak, Backstage, triage-copilot
directory) were single-instance with **no backups** — one PVC away from unrecoverable data loss.

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
| [aws_eks_pod_identity_association.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_pod_identity_association) | resource |
| [aws_iam_role.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_s3_bucket.backups](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_lifecycle_configuration.backups](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_ownership_controls.backups](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_policy.backups](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.backups](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.backups](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.backups](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_iam_policy_document.bucket](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.trust](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_bucket_name"></a> [bucket\_name](#input\_bucket\_name) | Name of the shared CNPG backup bucket (deterministic; per-cluster key prefixes live under it). | `string` | n/a | yes |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | EKS cluster name for the Pod Identity associations (the hub the CNPG clusters run on). | `string` | n/a | yes |
| <a name="input_clusters"></a> [clusters](#input\_clusters) | The CNPG clusters to grant backup access. Each gets its OWN key prefix (= name), its OWN least-privilege<br/>IAM role (scoped to that prefix), and a Pod Identity association binding the cluster's instance<br/>ServiceAccount to that role. `service_account` is the CNPG instance SA (defaults to the cluster name). | <pre>list(object({<br/>    name            = string<br/>    namespace       = string<br/>    service_account = string<br/>  }))</pre> | `[]` | no |
| <a name="input_create"></a> [create](#input\_create) | Create the backup bucket + per-cluster IAM/associations. | `bool` | `true` | no |
| <a name="input_force_destroy"></a> [force\_destroy](#input\_force\_destroy) | Allow deleting a non-empty bucket on destroy. Keep false for a real backup store. | `bool` | `false` | no |
| <a name="input_noncurrent_version_expiration_days"></a> [noncurrent\_version\_expiration\_days](#input\_noncurrent\_version\_expiration\_days) | Expire noncurrent object versions after this many days (hygiene only — Barman owns backup retention via the ObjectStore retentionPolicy). | `number` | `30` | no |
| <a name="input_role_name_prefix"></a> [role\_name\_prefix](#input\_role\_name\_prefix) | Prefix for the per-cluster IAM role names (role = <prefix>-<cluster>). | `string` | `"cnpg-backups"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the bucket, roles, and associations. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_bucket_arn"></a> [bucket\_arn](#output\_bucket\_arn) | The CNPG backup bucket ARN. |
| <a name="output_bucket_name"></a> [bucket\_name](#output\_bucket\_name) | The CNPG backup bucket name. |
| <a name="output_destination_paths"></a> [destination\_paths](#output\_destination\_paths) | Per-cluster Barman destinationPath (s3://<bucket>/<cluster>), keyed by cluster name. |
| <a name="output_role_arns"></a> [role\_arns](#output\_role\_arns) | Per-cluster backup IAM role ARN, keyed by cluster name (referenced by each cluster's Barman ObjectStore). |
<!-- END_TF_DOCS -->
