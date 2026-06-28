# Tailscale Admin

Manages tailnet-level Tailscale configuration: ACL policies, tailnet settings (HTTPS certificates), and OAuth client provisioning for the Kubernetes operator. Optionally stores OAuth credentials in AWS Secrets Manager so the `tailscale` K8s module can retrieve them without manual credential distribution. This module has no Kubernetes cluster dependencies and runs independently of the K8s control plane.

## Usage

```hcl
module "tailscale_admin" {
  source = "../../modules/tailscale-admin"

  acl_policy = jsonencode({
    acls = [
      { action = "accept", src = ["group:platform"], dst = ["*:*"] },
      { action = "accept", src = ["tag:k8s-operator"], dst = ["*:*"] },
    ]
    tagOwners = {
      "tag:k8s-operator" = ["group:platform"]
    }
    groups = {
      "group:platform" = ["user@example.com"]
    }
  })

  create_oauth_client  = true
  oauth_client_tags    = ["tag:k8s-operator"]
  secrets_manager_name = "platform/tailscale/oauth"

  tags = {
    Environment = "platform"
    ManagedBy   = "terraform"
  }
}
```

## Examples

### Disabled Module

```hcl
module "tailscale_admin" {
  source = "../../modules/tailscale-admin"

  create     = false
  acl_policy = "{}"
}
```

### ACL Only (No OAuth Client)

```hcl
module "tailscale_admin" {
  source = "../../modules/tailscale-admin"

  acl_policy          = file("tailscale-acl.json")
  create_oauth_client = false
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |
| <a name="requirement_tailscale"></a> [tailscale](#requirement\_tailscale) | ~> 0.29 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6.0 |
| <a name="provider_tailscale"></a> [tailscale](#provider\_tailscale) | ~> 0.29 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_secretsmanager_secret.oauth](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret_version.oauth](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [tailscale_acl.this](https://registry.terraform.io/providers/tailscale/tailscale/latest/docs/resources/acl) | resource |
| [tailscale_oauth_client.k8s_operator](https://registry.terraform.io/providers/tailscale/tailscale/latest/docs/resources/oauth_client) | resource |
| [tailscale_tailnet_settings.this](https://registry.terraform.io/providers/tailscale/tailscale/latest/docs/resources/tailnet_settings) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_acl_policy"></a> [acl\_policy](#input\_acl\_policy) | Tailscale ACL policy document (JSON or HuJSON) | `string` | n/a | yes |
| <a name="input_create"></a> [create](#input\_create) | Whether to create resources | `bool` | `true` | no |
| <a name="input_create_oauth_client"></a> [create\_oauth\_client](#input\_create\_oauth\_client) | Whether to create an OAuth client for the K8s operator | `bool` | `true` | no |
| <a name="input_https_enabled"></a> [https\_enabled](#input\_https\_enabled) | Enable HTTPS certificates for tailnet devices (required for Tailscale Ingress TLS) | `bool` | `true` | no |
| <a name="input_oauth_client_description"></a> [oauth\_client\_description](#input\_oauth\_client\_description) | Description for the OAuth client | `string` | `"K8s Operator managed by Terraform"` | no |
| <a name="input_oauth_client_scopes"></a> [oauth\_client\_scopes](#input\_oauth\_client\_scopes) | OAuth client permission scopes | `list(string)` | <pre>[<br/>  "devices:core",<br/>  "devices:routes",<br/>  "auth_keys"<br/>]</pre> | no |
| <a name="input_oauth_client_tags"></a> [oauth\_client\_tags](#input\_oauth\_client\_tags) | Tags that access tokens can assign to devices | `list(string)` | <pre>[<br/>  "tag:k8s-operator"<br/>]</pre> | no |
| <a name="input_secrets_manager_name"></a> [secrets\_manager\_name](#input\_secrets\_manager\_name) | Secrets Manager secret name for OAuth credentials | `string` | `"platform/tailscale/oauth"` | no |
| <a name="input_secrets_manager_recovery_window"></a> [secrets\_manager\_recovery\_window](#input\_secrets\_manager\_recovery\_window) | Number of days to retain a deleted secret (0 = immediate deletion) | `number` | `7` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to AWS resources | `map(string)` | `{}` | no |
| <a name="input_write_to_secrets_manager"></a> [write\_to\_secrets\_manager](#input\_write\_to\_secrets\_manager) | Write OAuth credentials to AWS Secrets Manager | `bool` | `true` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_acl_id"></a> [acl\_id](#output\_acl\_id) | The ACL resource ID |
| <a name="output_oauth_client_id"></a> [oauth\_client\_id](#output\_oauth\_client\_id) | OAuth client ID for the K8s operator |
| <a name="output_oauth_secret_arn"></a> [oauth\_secret\_arn](#output\_oauth\_secret\_arn) | ARN of the Secrets Manager secret containing OAuth credentials |
<!-- END_TF_DOCS -->

## Notes

- The ACL policy is applied with `overwrite_existing_content = true`, so it replaces the entire existing tailnet ACL. Coordinate with any manual ACL changes.
- OAuth client credentials are written to AWS Secrets Manager when both `create_oauth_client` and `write_to_secrets_manager` are true. The `tailscale` K8s module reads from this secret.
- The `secrets_manager_recovery_window` defaults to 7 days. Set to 0 for immediate deletion during development/testing (avoids name conflicts on recreate).
- This module requires the `tailscale` Terraform provider to be configured with an API key or OAuth credentials that have admin access to the tailnet.

## Related ADRs

- ADR-011: Tailscale Operator for Private Cluster Access
