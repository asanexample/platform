# Transit Gateway

Creates the Transit Gateway (hub) in the platform account and attaches the platform VPC for cross-account connectivity.

## Module

`infra/modules/aws/transit-gateway`

## Dependencies

- `networking` -- `../networking`

## Key Inputs

| Input | Value | Notes |
|-------|-------|-------|
| `name` | `platform-use1-tgw` | |
| `create_tgw` | `true` | This is the hub; spoke accounts attach via RAM share |
| `ram_share_principals` | `<PREPROD_ACCOUNT_ID>` | Shares TGW with preprod account via Resource Access Manager |
| `subnet_ids` | Transit subnets | Dedicated /28 subnets per AZ for TGW ENIs |
| `route_table_ids` | Private route tables | Adds TGW routes to private subnets |
| `destination_cidrs` | `10.101.0.0/16` | Routes preprod VPC CIDR through the TGW |

## Commands

```bash
# Plan
AWS_PROFILE=management terragrunt plan

# Apply
AWS_PROFILE=management terragrunt apply
```
