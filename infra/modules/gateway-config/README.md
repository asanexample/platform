# Gateway Config

Creates the Gateway API ingress stack: a cert-manager ClusterIssuer (Let's Encrypt production via Route53 DNS-01), a Cilium Gateway with HTTPS and HTTP listeners, per-hostname HTTPRoutes for backend services, and HTTP-to-HTTPS redirect routes. The Gateway uses the `cilium` GatewayClass (created by the Cilium Helm chart) and provisions an AWS NLB via infrastructure annotations. Supports both internet-facing and internal (VPN-only) NLB schemes.

## Usage

```hcl
module "gateway_config" {
  source = "../../modules/gateway-config"

  domain                 = "aws.refplat.org"
  letsencrypt_email      = "platform@refplat.org"
  route53_hosted_zone_id = "Z1234567890"
  route53_region         = "us-east-1"
  internal               = true

  routes = {
    argocd = {
      namespace = "argocd"
      service   = "argocd-server"
      port      = 443
    }
    hubble = {
      namespace = "kube-system"
      service   = "hubble-ui"
      port      = 80
    }
  }
}
```

## Examples

### Disabled Module

```hcl
module "gateway_config" {
  source = "../../modules/gateway-config"

  create                 = false
  domain                 = "aws.refplat.org"
  letsencrypt_email      = "platform@refplat.org"
  route53_hosted_zone_id = "Z1234567890"
}
```

### Internet-Facing Gateway

```hcl
module "gateway_config" {
  source = "../../modules/gateway-config"

  domain                 = "preprod.aws.refplat.org"
  letsencrypt_email      = "platform@refplat.org"
  route53_hosted_zone_id = "Z0987654321"
  internal               = false

  gateway_name      = "preprod-gateway"
  gateway_namespace = "default"

  routes = {
    app = {
      namespace = "team-acme"
      service   = "web"
      port      = 8080
    }
  }
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
| [kubernetes_manifest.cluster_issuer](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_manifest.gateway](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_manifest.http_redirect_routes](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_manifest.http_routes](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_domain"></a> [domain](#input\_domain) | Base domain for the gateway (e.g. aws.refplat.org) | `string` | n/a | yes |
| <a name="input_letsencrypt_email"></a> [letsencrypt\_email](#input\_letsencrypt\_email) | Email address for Let's Encrypt account registration | `string` | n/a | yes |
| <a name="input_route53_hosted_zone_id"></a> [route53\_hosted\_zone\_id](#input\_route53\_hosted\_zone\_id) | Route53 hosted zone ID for DNS01 solver | `string` | n/a | yes |
| <a name="input_cluster_issuer_name"></a> [cluster\_issuer\_name](#input\_cluster\_issuer\_name) | Name of the cert-manager ClusterIssuer | `string` | `"letsencrypt-prod"` | no |
| <a name="input_create"></a> [create](#input\_create) | Controls whether resources should be created | `bool` | `true` | no |
| <a name="input_gateway_name"></a> [gateway\_name](#input\_gateway\_name) | Name of the Gateway resource | `string` | `"platform-gateway"` | no |
| <a name="input_gateway_namespace"></a> [gateway\_namespace](#input\_gateway\_namespace) | Namespace for the Gateway resource | `string` | `"default"` | no |
| <a name="input_internal"></a> [internal](#input\_internal) | Use an internal NLB instead of internet-facing (requires VPN for access) | `bool` | `false` | no |
| <a name="input_route53_region"></a> [route53\_region](#input\_route53\_region) | AWS region for Route53 API calls | `string` | `"us-east-1"` | no |
| <a name="input_routes"></a> [routes](#input\_routes) | Map of hostname prefix to service routing config | <pre>map(object({<br/>    namespace = string<br/>    service   = string<br/>    port      = number<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_cluster_issuer_name"></a> [cluster\_issuer\_name](#output\_cluster\_issuer\_name) | Name of the ClusterIssuer |
| <a name="output_gateway_name"></a> [gateway\_name](#output\_gateway\_name) | Name of the Gateway resource |
| <a name="output_gateway_namespace"></a> [gateway\_namespace](#output\_gateway\_namespace) | Namespace of the Gateway resource |
| <a name="output_route_hostnames"></a> [route\_hostnames](#output\_route\_hostnames) | Map of route names to their FQDNs |
<!-- END_TF_DOCS -->

## Notes

- The GatewayClass `cilium` is not managed by this module -- it is created by the Cilium Helm chart when `gateway_api_enabled = true`.
- TLS certificates are obtained via Let's Encrypt DNS-01 challenge against Route53, which works even when the NLB is internal (no public HTTP access required).
- Each route creates both an HTTPS HTTPRoute and an HTTP-to-HTTPS 301 redirect route.
- The Gateway listener uses a wildcard hostname (`*.<domain>`), so all routes must be subdomains of the configured `domain`.
- When `internal = true`, the NLB uses the `internal` scheme and is only reachable through VPN (Tailscale) or VPC peering.

## Related ADRs

- ADR-017: Gateway API over Traditional Ingress
- ADR-029: Preprod Public Ingress via Gateway API
