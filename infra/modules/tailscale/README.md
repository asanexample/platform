# Tailscale

Deploys the Tailscale Kubernetes Operator via Helm and configures a subnet router for VPN access to private cluster networks. Creates a ProxyClass with `TS_USERSPACE=true` (required for compatibility with Cilium CNI), a Connector resource advertising specified CIDR ranges to the tailnet, and optional split DNS rules that route domain queries through VPC DNS resolvers. OAuth credentials for the operator are provided directly via variables (typically sourced from AWS Secrets Manager in the live unit). The module is cloud-agnostic -- only the live unit's provider configuration is cloud-specific.

## Usage

```hcl
module "tailscale" {
  source = "../../modules/tailscale"

  cluster_name       = "platform-use1-eks"
  helm_chart_version = "1.82.0"

  oauth_client_id     = data.aws_secretsmanager_secret_version.tailscale.secret_string_map["clientId"]
  oauth_client_secret = data.aws_secretsmanager_secret_version.tailscale.secret_string_map["clientSecret"]

  advertise_routes = ["10.100.0.0/16"]

  split_dns = {
    "us-east-1.eks.amazonaws.com" = ["10.100.0.2"]
  }

  tags = {
    Environment = "platform"
    ManagedBy   = "terraform"
  }
}
```

## Examples

### Disabled Module

```hcl
module "tailscale" {
  source = "../../modules/tailscale"

  create             = false
  cluster_name       = "platform-use1-eks"
  helm_chart_version = "1.82.0"
}
```

### Operator Only (No Subnet Router)

```hcl
module "tailscale" {
  source = "../../modules/tailscale"

  cluster_name        = "platform-use1-eks"
  helm_chart_version  = "1.82.0"
  oauth_client_id     = var.tailscale_client_id
  oauth_client_secret = var.tailscale_client_secret
  advertise_routes    = []
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | ~> 3.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | ~> 3.0 |
| <a name="requirement_tailscale"></a> [tailscale](#requirement\_tailscale) | ~> 0.29 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_helm"></a> [helm](#provider\_helm) | ~> 3.0 |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | ~> 3.0 |
| <a name="provider_null"></a> [null](#provider\_null) | n/a |
| <a name="provider_tailscale"></a> [tailscale](#provider\_tailscale) | ~> 0.29 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [helm_release.tailscale_operator](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [kubernetes_manifest.connector](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_manifest.proxy_class](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [null_resource.crd_finalizer_cleanup](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [tailscale_dns_split_nameservers.this](https://registry.terraform.io/providers/tailscale/tailscale/latest/docs/resources/dns_split_nameservers) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the EKS/AKS cluster (used for Connector naming) | `string` | n/a | yes |
| <a name="input_helm_chart_version"></a> [helm\_chart\_version](#input\_helm\_chart\_version) | Version of the Tailscale operator Helm chart | `string` | n/a | yes |
| <a name="input_advertise_routes"></a> [advertise\_routes](#input\_advertise\_routes) | CIDR ranges to advertise via the Tailscale subnet router | `list(string)` | `[]` | no |
| <a name="input_connector_hostname"></a> [connector\_hostname](#input\_connector\_hostname) | Hostname suffix for the Tailscale Connector device | `string` | `"subnet-router"` | no |
| <a name="input_create"></a> [create](#input\_create) | Controls whether resources should be created | `bool` | `true` | no |
| <a name="input_deployer_role_arn"></a> [deployer\_role\_arn](#input\_deployer\_role\_arn) | IAM role ARN to assume for destroy-time finalizer cleanup (the PlatformDeployer) | `string` | `""` | no |
| <a name="input_finalizer_clear_script"></a> [finalizer\_clear\_script](#input\_finalizer\_clear\_script) | Non-empty enables the destroy-time teardown cleanup script. Only checked for non-emptiness — the script itself is resolved at run time via the checkout's own `git rev-parse --show-toplevel`, not this value, so a worktree's different absolute path can't force a spurious null\_resource replace. Kept as a path-shaped string for unit-wiring compatibility (units still pass get\_repo\_root()). | `string` | `""` | no |
| <a name="input_helm_chart"></a> [helm\_chart](#input\_helm\_chart) | Name of the Helm chart | `string` | `"tailscale-operator"` | no |
| <a name="input_helm_release_name"></a> [helm\_release\_name](#input\_helm\_release\_name) | Name of the Helm release | `string` | `"tailscale-operator"` | no |
| <a name="input_helm_repository"></a> [helm\_repository](#input\_helm\_repository) | Repository URL for the Tailscale operator Helm chart | `string` | `"https://pkgs.tailscale.com/helmcharts"` | no |
| <a name="input_helm_timeout"></a> [helm\_timeout](#input\_helm\_timeout) | Timeout for Helm operations in seconds | `number` | `600` | no |
| <a name="input_helm_wait"></a> [helm\_wait](#input\_helm\_wait) | Whether to wait for Helm release to complete | `bool` | `true` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Kubernetes namespace to install the Tailscale operator into | `string` | `"tailscale-system"` | no |
| <a name="input_oauth_client_id"></a> [oauth\_client\_id](#input\_oauth\_client\_id) | Tailscale OAuth client ID (not needed when using generated oauth\_override.tf) | `string` | `""` | no |
| <a name="input_oauth_client_secret"></a> [oauth\_client\_secret](#input\_oauth\_client\_secret) | Tailscale OAuth client secret (not needed when using generated oauth\_override.tf) | `string` | `""` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region of the cluster (for destroy-time finalizer cleanup auth) | `string` | `""` | no |
| <a name="input_split_dns"></a> [split\_dns](#input\_split\_dns) | Map of domain to nameserver IPs for split DNS (created after subnet router is online) | `map(list(string))` | `{}` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_connector_name"></a> [connector\_name](#output\_connector\_name) | Name of the Tailscale Connector resource |
| <a name="output_helm_release_status"></a> [helm\_release\_status](#output\_helm\_release\_status) | Status of the Tailscale operator Helm release |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Kubernetes namespace where the Tailscale operator is installed |
| <a name="output_split_dns_domains"></a> [split\_dns\_domains](#output\_split\_dns\_domains) | List of configured split DNS domains |
<!-- END_TF_DOCS -->

## Notes

- The ProxyClass sets `TS_USERSPACE=true` because kernel-mode subnet routing conflicts with Cilium's datapath. This is required for all Cilium-based clusters.
- Split DNS is created in this module (not `tailscale-admin`) with an explicit `depends_on` on the Connector, ensuring the subnet router is online before DNS rules reference it.
- Finalizer cleanup `null_resource` blocks are included for both the Connector and ProxyClass to prevent destroy operations from blocking on operator finalizer processing.
- The `helm_chart_version` has no default and must be explicitly set.

## Related ADRs

- ADR-011: Tailscale Operator for Private Cluster Access
