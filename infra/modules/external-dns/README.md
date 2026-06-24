# ExternalDNS

Deploys ExternalDNS via Helm for managing AWS Route53 DNS records, with AWS identity via **EKS Pod Identity** (ADR-047). By default, watches Gateway API resources (HTTPRoute, GRPCRoute, TLSRoute) rather than Ingress or Service resources. Creates an IAM role with Route53 permissions and a Pod Identity association binding it to the `external-dns` ServiceAccount. The `txtOwnerId` is set to the cluster name to prevent multiple ExternalDNS instances from conflicting on the same hosted zone.

## Usage

```hcl
module "external_dns" {
  source = "../../modules/external-dns"

  cluster_name            = "platform-use1-eks"
  route53_hosted_zone_arn = "arn:aws:route53:::hostedzone/Z1234567890"
  domain_filters          = ["aws.refplat.org"]

  tags = {
    Environment = "platform"
    ManagedBy   = "terraform"
  }
}
```

## Examples

### Disabled Module

```hcl
module "external_dns" {
  source = "../../modules/external-dns"

  create       = false
  cluster_name = "platform-use1-eks"
}
```

### Upsert-Only Policy

```hcl
module "external_dns" {
  source = "../../modules/external-dns"

  cluster_name            = "platform-use1-eks"
  route53_hosted_zone_arn = "arn:aws:route53:::hostedzone/Z1234567890"
  policy                  = "upsert-only"
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
| [aws_eks_pod_identity_association.external_dns](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_pod_identity_association) | resource |
| [aws_iam_role.external_dns](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.external_dns_route53](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [helm_release.external_dns](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [aws_iam_policy_document.external_dns_route53](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.external_dns_trust](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the EKS cluster (used for IAM role naming and txtOwnerId) | `string` | n/a | yes |
| <a name="input_create"></a> [create](#input\_create) | Controls whether resources should be created | `bool` | `true` | no |
| <a name="input_domain_filters"></a> [domain\_filters](#input\_domain\_filters) | Limit DNS records to these domains | `list(string)` | `[]` | no |
| <a name="input_helm_chart"></a> [helm\_chart](#input\_helm\_chart) | Name of the Helm chart | `string` | `"external-dns"` | no |
| <a name="input_helm_chart_version"></a> [helm\_chart\_version](#input\_helm\_chart\_version) | Version of the external-dns Helm chart | `string` | `"1.16.1"` | no |
| <a name="input_helm_release_name"></a> [helm\_release\_name](#input\_helm\_release\_name) | Name of the Helm release | `string` | `"external-dns"` | no |
| <a name="input_helm_repository"></a> [helm\_repository](#input\_helm\_repository) | Repository URL for the external-dns Helm chart | `string` | `"https://kubernetes-sigs.github.io/external-dns/"` | no |
| <a name="input_helm_timeout"></a> [helm\_timeout](#input\_helm\_timeout) | Timeout for Helm operations in seconds | `number` | `600` | no |
| <a name="input_helm_wait"></a> [helm\_wait](#input\_helm\_wait) | Whether to wait for Helm release to complete | `bool` | `true` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Kubernetes namespace to install external-dns into | `string` | `"external-dns"` | no |
| <a name="input_policy"></a> [policy](#input\_policy) | DNS record management policy (sync, upsert-only, create-only) | `string` | `"sync"` | no |
| <a name="input_route53_hosted_zone_arn"></a> [route53\_hosted\_zone\_arn](#input\_route53\_hosted\_zone\_arn) | ARN of the Route53 hosted zone for DNS record management | `string` | `""` | no |
| <a name="input_sources"></a> [sources](#input\_sources) | Kubernetes resource types to watch for DNS records | `list(string)` | <pre>[<br/>  "gateway-httproute",<br/>  "gateway-grpcroute",<br/>  "gateway-tlsroute"<br/>]</pre> | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_helm_release_status"></a> [helm\_release\_status](#output\_helm\_release\_status) | Status of the external-dns Helm release |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Kubernetes namespace where external-dns is installed |
| <a name="output_role_arn"></a> [role\_arn](#output\_role\_arn) | ARN of the external-dns IAM role (bound to the SA via EKS Pod Identity) |
<!-- END_TF_DOCS -->

## Notes

- Default sources are `gateway-httproute`, `gateway-grpcroute`, and `gateway-tlsroute`. Change `sources` to `["ingress", "service"]` if using traditional Ingress resources instead of Gateway API.
- The `policy` variable controls record lifecycle: `sync` (default) creates and deletes records, `upsert-only` creates but never deletes, `create-only` creates once and never updates.
- AWS identity is via **EKS Pod Identity** (ADR-047): the IAM role trusts `pods.eks.amazonaws.com` and a `aws_eks_pod_identity_association` binds it to the `external-dns` ServiceAccount — no `eks.amazonaws.com/role-arn` annotation and no OIDC provider needed (the `eks-pod-identity-agent` addon injects creds at pod launch). The IAM policy grants `route53:ChangeResourceRecordSets` on the specified zone and `route53:ListHostedZones` globally.

## Related ADRs

- ADR-022: DNS Architecture
- ADR-047: EKS Pod Identity as the Standard for Pod AWS Identity
