# gateway

The platform's **foundational shared ingress**: the cert-manager **ClusterIssuer** (Let's Encrypt prod, Route53
DNS-01) and the **Cilium Gateway** (`*.<domain>` wildcard HTTPS listener + wildcard TLS cert, plus an HTTP
listener for 301 redirects), fronted by an internal NLB.

Split out of `gateway-config` (ADR-053/059) so the Gateway is created **early** — before the apps and before
`keycloak-config`, which must reach Keycloak through its gateway-exposed endpoint during apply. Per-app
**HTTPRoutes attach here via `parentRef`** and are owned by each app (e.g. the `keycloak` module self-routes) or
by the `gateway-config` routes unit — never by this module.

## Usage

```hcl
module "gateway" {
  source = "../../modules/gateway"

  domain                 = "aws.refplat.org"
  internal               = true
  letsencrypt_email      = "platform@example.com"
  route53_hosted_zone_id = "Z0123456789"
  route53_region         = "us-east-1"
}
```

Defaults — `gateway_name = "platform-gateway"`, `gateway_namespace = "default"`, `cluster_issuer_name =
"letsencrypt-prod"` — are the contract every HTTPRoute's `parentRef` depends on; change them only in lockstep
with all routes.

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
| [kubernetes_manifest.cluster_issuer](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_manifest.gateway](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_domain"></a> [domain](#input\_domain) | Base domain for the gateway (e.g. aws.refplat.org). The wildcard listener serves *.<domain>. | `string` | n/a | yes |
| <a name="input_letsencrypt_email"></a> [letsencrypt\_email](#input\_letsencrypt\_email) | Email address for Let's Encrypt account registration | `string` | n/a | yes |
| <a name="input_route53_hosted_zone_id"></a> [route53\_hosted\_zone\_id](#input\_route53\_hosted\_zone\_id) | Route53 hosted zone ID for the DNS01 solver | `string` | n/a | yes |
| <a name="input_cluster_issuer_name"></a> [cluster\_issuer\_name](#input\_cluster\_issuer\_name) | Name of the cert-manager ClusterIssuer | `string` | `"letsencrypt-prod"` | no |
| <a name="input_create"></a> [create](#input\_create) | Controls whether resources should be created | `bool` | `true` | no |
| <a name="input_gateway_name"></a> [gateway\_name](#input\_gateway\_name) | Name of the Gateway resource. App HTTPRoutes attach to this via parentRef. | `string` | `"platform-gateway"` | no |
| <a name="input_gateway_namespace"></a> [gateway\_namespace](#input\_gateway\_namespace) | Namespace for the Gateway resource. App HTTPRoutes reference this namespace in their parentRef. | `string` | `"default"` | no |
| <a name="input_internal"></a> [internal](#input\_internal) | Use an internal NLB instead of internet-facing (requires VPN for access) | `bool` | `false` | no |
| <a name="input_route53_region"></a> [route53\_region](#input\_route53\_region) | AWS region for Route53 API calls | `string` | `"us-east-1"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_cluster_issuer_name"></a> [cluster\_issuer\_name](#output\_cluster\_issuer\_name) | Name of the cert-manager ClusterIssuer. |
| <a name="output_gateway_name"></a> [gateway\_name](#output\_gateway\_name) | Name of the Gateway resource (for app HTTPRoute parentRefs). |
| <a name="output_gateway_namespace"></a> [gateway\_namespace](#output\_gateway\_namespace) | Namespace of the Gateway resource (for app HTTPRoute parentRefs). |
<!-- END_TF_DOCS -->

## Related ADRs

- ADR-053 / ADR-059: identity strategy + the Gateway split (keycloak-config reachability)
