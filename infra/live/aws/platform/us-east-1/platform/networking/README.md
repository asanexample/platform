# AWS Networking - US East 1 (Platform)

## Overview

Deploys the foundational VPC, subnets, gateways, and flow logs for the platform environment in us-east-1.

## Configuration Details

### Purpose

- Provisions a VPC with six subnet tiers across three availability zones (us-east-1a/b/c)
- Creates internet gateway and a single NAT gateway for private subnet egress
- Pre-tags subnets and creates security groups required by EKS
- Enables VPC flow logs for network visibility

### Dependencies

None. This is the foundational layer for the platform environment.

### Key Configuration Settings

- **VPC**:
  - CIDR: `10.100.0.0/16` (defined in `network.hcl`)
  - Name pattern: `{env}-{region_abbv}-vpc`
  - Flow logs: enabled, 30-day retention

- **Subnets** (per AZ, 3 AZs):
  - kubernetes: private, /26 (62 IPs)
  - endpoints: private, /26 (62 IPs)
  - firewall: private, /26 (62 IPs)
  - services: private, /27 (30 IPs)
  - public: public, /28 (14 IPs)
  - transit: private, /28 (14 IPs)

- **Gateways**:
  - Internet gateway: enabled
  - NAT gateway: single (cost-efficient)

- **EKS Networking**:
  - Enabled, pre-tags subnets for cluster `{env}-{region_abbv}-eks`

## Usage

```bash
cd infra/live/aws/platform/us-east-1/platform/networking
terragrunt plan
terragrunt apply
```

## Dependencies on this Configuration

- **eks**: consumes VPC, kubernetes subnet IDs, and EKS security group ID
- **ssm-bastion**: consumes VPC ID and kubernetes subnet ID

## Implementation Notes

Address space and subnet layout are defined in `network.hcl` at the region level, which is the authoritative source for CIDR allocation. The subnet tier math uses `cidrsubnet` nesting to carve per-AZ ranges from the /16.
