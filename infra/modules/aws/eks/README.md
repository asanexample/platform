# EKS

Creates an Amazon EKS cluster with an IAM service role, OIDC provider for IRSA (IAM Roles for Service Accounts), optional KMS envelope encryption for Kubernetes secrets, and EKS access entries for IAM-to-Kubernetes RBAC mapping. The cluster is configured with `bootstrap_self_managed_addons = false` (BYOCNI mode), meaning the AWS VPC CNI is not installed and Cilium must be deployed before nodes can join. Authentication mode is set to `API_AND_CONFIG_MAP`.

## Usage

```hcl
module "eks" {
  source = "../../modules/aws/eks"

  cluster_name       = "platform-use1-eks"
  kubernetes_version = "1.35"
  subnet_ids         = [for k, v in module.networking.subnet_ids : v if can(regex("kubernetes$", k))]

  additional_security_group_ids = [module.networking.eks_security_group_id]

  endpoint_private_access = true
  endpoint_public_access  = false

  enable_secrets_encryption = true

  access_entries = {
    platform-admin = {
      principal_arn = "arn:aws:iam::<PLATFORM_ACCOUNT_ID>:role/PlatformAdmin"
      policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
      scope_type    = "cluster"
    }
    platform-deployer = {
      principal_arn = "arn:aws:iam::<PLATFORM_ACCOUNT_ID>:role/PlatformDeployer"
      policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
      scope_type    = "cluster"
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
module "eks" {
  source = "../../modules/aws/eks"
  create = false

  cluster_name = "unused"
  subnet_ids   = []
}
```

### Public Cluster with Add-ons

```hcl
module "eks" {
  source = "../../modules/aws/eks"

  cluster_name            = "preprod-use1-eks"
  subnet_ids              = ["subnet-aaa", "subnet-bbb"]
  endpoint_public_access  = true
  endpoint_private_access = true
  public_access_cidrs     = ["203.0.113.0/24"]

  eks_addons = {
    vpc-cni = {}
  }

  tags = {
    Environment = "preprod"
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
| <a name="provider_tls"></a> [tls](#provider\_tls) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_eks_access_entry.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_access_entry) | resource |
| [aws_eks_access_policy_association.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_access_policy_association) | resource |
| [aws_eks_addon.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_addon) | resource |
| [aws_eks_cluster.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_cluster) | resource |
| [aws_iam_openid_connect_provider.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_openid_connect_provider) | resource |
| [aws_iam_role.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.cluster_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.vpc_resource_controller](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_kms_alias.eks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.eks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [tls_certificate.cluster](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/data-sources/certificate) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the EKS cluster | `string` | n/a | yes |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Subnet IDs for the EKS cluster ENIs | `list(string)` | n/a | yes |
| <a name="input_access_entries"></a> [access\_entries](#input\_access\_entries) | IAM principal to Kubernetes access policy mappings | <pre>map(object({<br/>    principal_arn = string<br/>    policy_arn    = string<br/>    type          = optional(string, "STANDARD")<br/>    scope_type    = optional(string, "cluster")<br/>    namespaces    = optional(list(string))<br/>  }))</pre> | `{}` | no |
| <a name="input_additional_security_group_ids"></a> [additional\_security\_group\_ids](#input\_additional\_security\_group\_ids) | Additional security group IDs to attach to the cluster (e.g. networking module's EKS SG) | `list(string)` | `[]` | no |
| <a name="input_create"></a> [create](#input\_create) | Whether to create resources in this module | `bool` | `true` | no |
| <a name="input_eks_addons"></a> [eks\_addons](#input\_eks\_addons) | EKS managed add-ons to install (e.g. coredns, kube-proxy) | <pre>map(object({<br/>    most_recent = optional(bool, true)<br/>  }))</pre> | `{}` | no |
| <a name="input_enable_secrets_encryption"></a> [enable\_secrets\_encryption](#input\_enable\_secrets\_encryption) | Enable KMS envelope encryption for Kubernetes secrets | `bool` | `true` | no |
| <a name="input_enabled_cluster_log_types"></a> [enabled\_cluster\_log\_types](#input\_enabled\_cluster\_log\_types) | EKS control plane log types to enable | `list(string)` | <pre>[<br/>  "api",<br/>  "audit",<br/>  "authenticator",<br/>  "controllerManager",<br/>  "scheduler"<br/>]</pre> | no |
| <a name="input_endpoint_private_access"></a> [endpoint\_private\_access](#input\_endpoint\_private\_access) | Enable private API server endpoint | `bool` | `true` | no |
| <a name="input_endpoint_public_access"></a> [endpoint\_public\_access](#input\_endpoint\_public\_access) | Enable public API server endpoint | `bool` | `true` | no |
| <a name="input_kubernetes_version"></a> [kubernetes\_version](#input\_kubernetes\_version) | Kubernetes version for the EKS cluster | `string` | `"1.35"` | no |
| <a name="input_public_access_cidrs"></a> [public\_access\_cidrs](#input\_public\_access\_cidrs) | CIDR blocks allowed to access the public API endpoint | `list(string)` | <pre>[<br/>  "0.0.0.0/0"<br/>]</pre> | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_cluster_arn"></a> [cluster\_arn](#output\_cluster\_arn) | The ARN of the EKS cluster |
| <a name="output_cluster_certificate_authority"></a> [cluster\_certificate\_authority](#output\_cluster\_certificate\_authority) | Base64-encoded certificate authority data for the cluster |
| <a name="output_cluster_endpoint"></a> [cluster\_endpoint](#output\_cluster\_endpoint) | The endpoint for the EKS API server |
| <a name="output_cluster_id"></a> [cluster\_id](#output\_cluster\_id) | The name/ID of the EKS cluster |
| <a name="output_cluster_security_group_id"></a> [cluster\_security\_group\_id](#output\_cluster\_security\_group\_id) | The EKS-managed cluster security group ID (auto-created by EKS) |
| <a name="output_cluster_version"></a> [cluster\_version](#output\_cluster\_version) | The Kubernetes version of the cluster |
| <a name="output_kms_key_arn"></a> [kms\_key\_arn](#output\_kms\_key\_arn) | The ARN of the KMS key used for secrets encryption |
| <a name="output_oidc_provider_arn"></a> [oidc\_provider\_arn](#output\_oidc\_provider\_arn) | The ARN of the IAM OIDC provider for IRSA |
| <a name="output_oidc_provider_url"></a> [oidc\_provider\_url](#output\_oidc\_provider\_url) | The OIDC issuer URL (without https:// prefix) for IRSA trust policies |
<!-- END_TF_DOCS -->

## Notes

- BYOCNI mode (`bootstrap_self_managed_addons = false`) means no CNI, kube-proxy, or CoreDNS is installed by default. Cilium must be deployed before node groups are created, and CoreDNS should be installed via the separate `eks-addons` module after nodes are ready.
- The `eks_addons` variable on this module is for add-ons that can be installed at cluster creation time. For add-ons that depend on CNI and nodes (e.g., CoreDNS), use the `eks-addons` module instead.
- All five control plane log types are enabled by default: `api`, `audit`, `authenticator`, `controllerManager`, `scheduler`.
- The OIDC provider is always created when the cluster is created, enabling IRSA for workloads.
- KMS key rotation is enabled by default for secrets encryption.

## Related ADRs

- ADR-009: EKS Component Separation
- ADR-010: Private-Only EKS API Endpoint
