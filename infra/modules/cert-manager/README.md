# cert-manager

Deploys cert-manager via Helm with Gateway API support enabled, using AWS Route53 for ACME DNS-01 challenge solving. AWS identity is via **EKS Pod Identity** (ADR-047): an IAM role with Route53 DNS-01 permissions is created and bound to the `cert-manager` controller ServiceAccount through a Pod Identity association. The Helm chart installs CRDs automatically.

## Usage

```hcl
module "cert_manager" {
  source = "../../modules/cert-manager"

  cluster_name            = "platform-use1-eks"
  route53_hosted_zone_arn = "arn:aws:route53:::hostedzone/Z1234567890"

  tags = {
    Environment = "platform"
    ManagedBy   = "terraform"
  }
}
```

## Examples

### Disabled Module

```hcl
module "cert_manager" {
  source = "../../modules/cert-manager"

  create       = false
  cluster_name = "platform-use1-eks"
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | ~> 3.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6.0 |
| <a name="provider_helm"></a> [helm](#provider\_helm) | ~> 3.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_eks_pod_identity_association.cert_manager](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_pod_identity_association) | resource |
| [aws_iam_role.cert_manager](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.cert_manager_route53](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [helm_release.cert_manager](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [aws_iam_policy_document.cert_manager_route53](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.cert_manager_trust](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the EKS cluster (used for IAM role naming) | `string` | n/a | yes |
| <a name="input_create"></a> [create](#input\_create) | Controls whether resources should be created | `bool` | `true` | no |
| <a name="input_helm_chart"></a> [helm\_chart](#input\_helm\_chart) | Name of the Helm chart | `string` | `"cert-manager"` | no |
| <a name="input_helm_chart_version"></a> [helm\_chart\_version](#input\_helm\_chart\_version) | Version of the cert-manager Helm chart | `string` | `"1.17.1"` | no |
| <a name="input_helm_release_name"></a> [helm\_release\_name](#input\_helm\_release\_name) | Name of the Helm release | `string` | `"cert-manager"` | no |
| <a name="input_helm_repository"></a> [helm\_repository](#input\_helm\_repository) | Repository URL for the cert-manager Helm chart | `string` | `"https://charts.jetstack.io"` | no |
| <a name="input_helm_timeout"></a> [helm\_timeout](#input\_helm\_timeout) | Timeout for Helm operations in seconds | `number` | `600` | no |
| <a name="input_helm_wait"></a> [helm\_wait](#input\_helm\_wait) | Whether to wait for Helm release to complete | `bool` | `true` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Kubernetes namespace to install cert-manager into | `string` | `"cert-manager"` | no |
| <a name="input_route53_hosted_zone_arn"></a> [route53\_hosted\_zone\_arn](#input\_route53\_hosted\_zone\_arn) | ARN of the Route53 hosted zone for DNS01 challenge solving | `string` | `""` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all resources | `map(string)` | `{}` | no |
| <a name="input_webhook_host_network"></a> [webhook\_host\_network](#input\_webhook\_host\_network) | Run the cert-manager webhook on hostNetwork (node VPC IP) with securePort moved off 10250. Required on EKS with an overlay CNI (Cilium cluster-pool), where the managed control plane cannot route to overlay pod IPs. Leave false for VPC-routable (ENI) datapaths. | `bool` | `false` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_helm_release_status"></a> [helm\_release\_status](#output\_helm\_release\_status) | Status of the cert-manager Helm release |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Kubernetes namespace where cert-manager is installed |
| <a name="output_role_arn"></a> [role\_arn](#output\_role\_arn) | ARN of the cert-manager IAM role (bound to the SA via EKS Pod Identity) |
<!-- END_TF_DOCS -->

## Notes

- AWS identity is via **EKS Pod Identity** (ADR-047): the IAM role trusts `pods.eks.amazonaws.com` and a `aws_eks_pod_identity_association` binds it to the `cert-manager` controller SA — no `eks.amazonaws.com/role-arn` annotation and no OIDC provider. The IAM policy grants `route53:GetChange`, `route53:ChangeResourceRecordSets`/`ListResourceRecordSets` on the specified hosted zone, and `route53:ListHostedZones*` globally (DNS-01).
- Gateway API integration is enabled by default (`enableGatewayAPI = true`), so cert-manager watches Gateway and HTTPRoute resources for TLS certificate requests.
- The `fsGroup: 1001` security context is set to avoid permission issues with cert-manager's key storage.
- The Helm release uses `replace = true`, so failed installs are replaced rather than upgraded.

## Related ADRs

- ADR-047: EKS Pod Identity as the Standard for Pod AWS Identity
