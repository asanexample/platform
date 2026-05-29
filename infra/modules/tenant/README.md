# Tenant

Provisions multi-tenant isolation boundaries on a shared Kubernetes cluster. Supports two modes: `namespace` (default) creates a dedicated namespace with resource quotas, limit ranges, and network policies; `vcluster` delegates to the `vcluster` module to create a virtual cluster. Namespace-mode tenants get a default-deny ingress NetworkPolicy, an allow rule for the Gateway namespace and kube-system, a CiliumNetworkPolicy allowing the Cilium `ingress` identity (used by the Gateway API Envoy proxy), and a permissive egress policy with DNS access.

## Usage

```hcl
module "tenants" {
  source = "../../modules/tenant"

  environment = "preprod"
  region_abbv = "use1"

  gateway_namespace = "default"

  tenants = {
    acme = {
      mode = "namespace"
      resource_quota = {
        cpu    = "8"
        memory = "16Gi"
        pods   = 40
      }
    }
    beta = {
      mode = "namespace"
    }
  }

  tags = {
    Environment = "preprod"
    ManagedBy   = "terraform"
  }
}
```

## Examples

### Disabled Module

```hcl
module "tenants" {
  source = "../../modules/tenant"

  create      = false
  environment = "preprod"
  region_abbv = "use1"
}
```

### vCluster Mode (Deferred)

```hcl
module "tenants" {
  source = "../../modules/tenant"

  environment = "preprod"
  region_abbv = "use1"

  tenants = {
    isolated = {
      mode = "vcluster"
    }
  }
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | >= 3.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | >= 2.10.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | >= 2.10.0 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_vcluster"></a> [vcluster](#module\_vcluster) | ../vcluster | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [kubernetes_limit_range.tenant](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/limit_range) | resource |
| [kubernetes_manifest.tenant_allow_gateway_envoy](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_namespace.tenant](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace) | resource |
| [kubernetes_network_policy.tenant_allow_dns](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/network_policy) | resource |
| [kubernetes_network_policy.tenant_allow_gateway](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/network_policy) | resource |
| [kubernetes_network_policy.tenant_default_deny](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/network_policy) | resource |
| [kubernetes_resource_quota.tenant](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/resource_quota) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name | `string` | n/a | yes |
| <a name="input_region_abbv"></a> [region\_abbv](#input\_region\_abbv) | Abbreviated region name | `string` | n/a | yes |
| <a name="input_create"></a> [create](#input\_create) | Whether to create tenant resources | `bool` | `true` | no |
| <a name="input_gateway_namespace"></a> [gateway\_namespace](#input\_gateway\_namespace) | Namespace where the Gateway resource lives (for NetworkPolicy allow rules) | `string` | `"default"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all resources | `map(string)` | `{}` | no |
| <a name="input_tenants"></a> [tenants](#input\_tenants) | Map of tenant names to their configuration | <pre>map(object({<br/>    mode = optional(string, "namespace")<br/>    resource_quota = optional(object({<br/>      cpu    = optional(string, "4")<br/>      memory = optional(string, "8Gi")<br/>      pods   = optional(number, 20)<br/>    }), {})<br/>  }))</pre> | `{}` | no |
| <a name="input_vcluster_chart_version"></a> [vcluster\_chart\_version](#input\_vcluster\_chart\_version) | vCluster Helm chart version | `string` | `"0.34.1"` | no |
| <a name="input_vcluster_persistence_enabled"></a> [vcluster\_persistence\_enabled](#input\_vcluster\_persistence\_enabled) | Enable persistent volume for vCluster data (requires a working StorageClass + CSI driver) | `bool` | `true` | no |
| <a name="input_vcluster_storage_class"></a> [vcluster\_storage\_class](#input\_vcluster\_storage\_class) | StorageClass for vCluster persistent volume | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_all_namespaces"></a> [all\_namespaces](#output\_all\_namespaces) | List of all tenant namespaces (both modes) |
| <a name="output_namespace_tenants"></a> [namespace\_tenants](#output\_namespace\_tenants) | Map of namespace-mode tenant names to their namespace |
| <a name="output_vcluster_tenants"></a> [vcluster\_tenants](#output\_vcluster\_tenants) | Map of vcluster-mode tenant names to their vCluster details |
<!-- END_TF_DOCS -->

## Notes

- Namespace-mode tenants are named `team-<key>` (e.g., tenant key `acme` gets namespace `team-acme`).
- The CiliumNetworkPolicy allows traffic from `ingress`, `remote-node`, and `host` entities so that the Cilium Gateway API Envoy proxy (which uses the reserved `ingress` identity) can reach tenant pods.
- Default container limits are 500m CPU / 512Mi memory with requests of 100m / 128Mi, applied via LimitRange.
- vCluster mode is currently deferred (ADR-033) because OSS vCluster cannot sync HTTPRoute CRDs to the host cluster's Gateway. All teams should use `namespace` mode.
