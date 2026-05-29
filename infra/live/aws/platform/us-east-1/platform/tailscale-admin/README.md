# Tailscale Admin

Manages tailnet-wide configuration: ACL policy, OAuth clients, and auto-approvers. Also replicates Tailscale secrets to the preprod account.

## Module

`infra/modules/tailscale-admin`

## Dependencies

None.

## Key Inputs

| Input | Value | Notes |
|-------|-------|-------|
| `acl_policy` | HuJSON ACL document | Grants all-to-all access, auto-approves `10.100.0.0/16` and `10.101.0.0/16` routes for `tag:k8s-operator` and `tag:k8s`, enables SSH with `check` action |
| `create_oauth_client` | `true` | Creates OAuth client for the K8s operator with `tag:k8s-operator` |
| `secrets_manager_name` | `platform/tailscale/oauth` | Stores OAuth credentials in platform account Secrets Manager |

Also generates Terraform resources to replicate OAuth and API key secrets to the preprod account (`<PREPROD_ACCOUNT_ID>`) via `aws.preprod` provider alias.

## Commands

```bash
# Plan
AWS_PROFILE=management terragrunt plan

# Apply
AWS_PROFILE=management terragrunt apply
```
