# transit-gateway

Attaches the preprod VPC to the platform account's Transit Gateway as a spoke. Enables cross-account VPC connectivity for private EKS API access and service communication.

## Module

`infra/modules/aws/transit-gateway`

## Dependencies

- `networking` — `../networking`
- `eks` — `../eks`
- `platform_tgw` — `../../../../platform/us-east-1/platform/transit-gateway` (cross-environment reference to the platform hub TGW)

## Key Inputs

| Input | Value | Notes |
|-------|-------|-------|
| `create_tgw` | `false` | Spoke mode — does not create a new TGW |
| `transit_gateway_id` | From platform TGW output | Attaches to the existing hub TGW |
| `ram_share_arn` | From platform TGW output | Accepts the RAM share to use the shared TGW |
| `subnet_ids` | Transit subnets only | Uses `/28` transit subnets for TGW ENIs |
| `destination_cidrs` | `["10.100.0.0/16"]` | Routes to platform VPC CIDR via TGW |
| `security_group_ingress_cidrs` | `["10.100.0.0/16"]` | Allows inbound traffic from platform VPC |

## Commands

```bash
# Plan
AWS_PROFILE=management terragrunt plan

# Apply
AWS_PROFILE=management terragrunt apply
```
