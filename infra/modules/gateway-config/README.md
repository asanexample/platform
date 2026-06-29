# Gateway Config

Creates the **per-app HTTPRoutes** (and HTTP→HTTPS redirect routes) that attach to the platform's shared Cilium
Gateway. The foundational **Gateway + cert-manager ClusterIssuer** were split into the [`gateway`](../gateway/)
module (ADR-053/059) so they come up early; this module references that Gateway by name (`gateway_name` /
`gateway_namespace`) and owns only the routes. (Keycloak self-owns its route in the [`keycloak`](../keycloak/)
module so its endpoint is live before keycloak-config configures it.)

## Usage

```hcl
module "gateway_config" {
  source = "../../modules/gateway-config"

  domain            = "aws.refplat.org"
  gateway_name      = module.gateway.gateway_name      # from the `gateway` unit
  gateway_namespace = module.gateway.gateway_namespace

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

  create = false
  domain = "aws.refplat.org"
}
```

### Routes on a differently-named Gateway

```hcl
module "gateway_config" {
  source = "../../modules/gateway-config"

  domain            = "preprod.aws.refplat.org"
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
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | ~> 3.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | ~> 3.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [kubernetes_manifest.http_redirect_routes](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_manifest.http_routes](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_domain"></a> [domain](#input\_domain) | Base domain for the routes (e.g. aws.refplat.org). Route hostnames are <key>.<domain>. | `string` | n/a | yes |
| <a name="input_create"></a> [create](#input\_create) | Controls whether resources should be created | `bool` | `true` | no |
| <a name="input_gateway_name"></a> [gateway\_name](#input\_gateway\_name) | Name of the shared Gateway to attach routes to (from the gateway unit). | `string` | `"platform-gateway"` | no |
| <a name="input_gateway_namespace"></a> [gateway\_namespace](#input\_gateway\_namespace) | Namespace of the shared Gateway (parentRef). | `string` | `"default"` | no |
| <a name="input_routes"></a> [routes](#input\_routes) | Map of hostname prefix to service routing config | <pre>map(object({<br/>    namespace = string<br/>    service   = string<br/>    port      = number<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
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
