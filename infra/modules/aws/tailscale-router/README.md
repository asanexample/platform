# Tailscale Subnet Router

Deploys a standalone EC2 instance that runs the Tailscale client as a **subnet
router**, advertising an in-VPC CIDR to the tailnet. Unlike the in-cluster Tailscale
Connector, this router lives **outside the cluster lifecycle** — it survives node
scale-to-zero (parking) and cluster teardown/rebuild, so private reach to the VPC and
the EKS API (ADR-010) does not die with the cluster.

The instance is a Graviton (`t4g.nano`) Amazon Linux 2023 arm64 box in a private
(NAT-egress) subnet, with IMDSv2 required, an encrypted root volume, and no inbound
security-group rules (debug/patch access is via SSM Session Manager only). It runs in
**kernel routing mode** — a standalone host has no Cilium, so the userspace-networking
workaround the in-cluster router needs does not apply.

At boot it reads a Tailscale **OAuth client credential** from Secrets Manager (scoped
by a least-privilege instance-profile policy) and uses it as an auth key. Advertising a
tag that is (a) owned by the OAuth client and (b) present in the tailnet
`autoApprovers` for the advertised routes means the device is preauthorized and its
routes self-approve — no manual admin approval.

Because the router's forwarded traffic is SNAT'd to its own private IP, any in-VPC
target it forwards to must admit that IP. For the private EKS API specifically, open
the cluster security group to the VPC CIDR via the `eks` module's
`additional_api_ingress_cidrs`.

## Usage

```hcl
module "tailscale_router" {
  source = "../../modules/aws/tailscale-router"

  name      = "platform-use1-tsrouter"
  region    = "us-east-1"
  vpc_id    = module.networking.vpc_id
  subnet_id = module.networking.subnet_ids["snet-...-kubernetes"]

  advertise_routes = [module.networking.vpc_cidr_block]
  advertise_tags   = ["tag:k8s-operator"]
  auth_secret_id   = "platform/tailscale/oauth"

  tags = {
    Environment = "platform"
    ManagedBy   = "opentofu"
  }
}
```

### Disabled Module

```hcl
module "tailscale_router" {
  source = "../../modules/aws/tailscale-router"
  create = false

  name             = "unused"
  region           = "us-east-1"
  vpc_id           = "vpc-xxx"
  subnet_id        = "subnet-xxx"
  advertise_routes = ["10.0.0.0/16"]
  auth_secret_id   = "unused"
}
```

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
| [aws_iam_instance_profile.router](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_role.router](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.read_auth_secret](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.ssm](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_instance.router](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance) | resource |
| [aws_security_group.router](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_egress_rule.advertised_routes](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.stun](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.wireguard](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_secretsmanager_secret.auth](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/secretsmanager_secret) | data source |
| [aws_ssm_parameter.al2023_arm64](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ssm_parameter) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_advertise_routes"></a> [advertise\_routes](#input\_advertise\_routes) | CIDR blocks advertised into the tailnet as subnet routes (e.g. the VPC CIDR). For routes to auto-approve, each must be covered by the tailnet autoApprovers for one of advertise\_tags. | `list(string)` | n/a | yes |
| <a name="input_auth_secret_id"></a> [auth\_secret\_id](#input\_auth\_secret\_id) | Secrets Manager secret ID holding the Tailscale OAuth client credential as JSON ({clientId, clientSecret}). The instance reads clientSecret at boot and uses it as its auth key. | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Name prefix for all resources and the Tailscale device hostname | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | AWS region — used by the instance to fetch its auth secret at boot | `string` | n/a | yes |
| <a name="input_subnet_id"></a> [subnet\_id](#input\_subnet\_id) | Private subnet ID for the router instance. MUST have NAT egress so the box can reach Tailscale's coordination/DERP servers and install packages at boot. | `string` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID to place the subnet router in | `string` | n/a | yes |
| <a name="input_advertise_tags"></a> [advertise\_tags](#input\_advertise\_tags) | Tailscale ACL tags advertised for the router device. Must be owned by the auth credential's OAuth client and present in the tailnet autoApprovers for the advertised routes to self-approve. | `list(string)` | <pre>[<br/>  "tag:k8s-operator"<br/>]</pre> | no |
| <a name="input_create"></a> [create](#input\_create) | Whether to create resources in this module | `bool` | `true` | no |
| <a name="input_instance_type"></a> [instance\_type](#input\_instance\_type) | EC2 instance type (Graviton/arm64 — the AMI is arm64) | `string` | `"t4g.nano"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_instance_id"></a> [instance\_id](#output\_instance\_id) | EC2 instance ID of the Tailscale subnet router (SSM session target) |
| <a name="output_private_ip"></a> [private\_ip](#output\_private\_ip) | Private IP of the router — the SNAT source that in-VPC targets (e.g. the EKS API SG) see |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | Security group ID of the router |
<!-- END_TF_DOCS -->
