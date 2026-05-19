# SSM Bastion - US East 1 (Platform)

## Overview

Deploys an SSM-managed bastion host for secure, private access to the EKS cluster without SSH keys or public IPs.

## Configuration Details

### Purpose

- Provisions a lightweight EC2 instance accessible only through AWS Systems Manager Session Manager
- Adds an ingress rule to the EKS cluster security group so the bastion can reach the API server
- Provides a jump point for kubectl access to the private EKS endpoint

### Dependencies

- **networking**: provides VPC ID and kubernetes subnet ID for bastion placement
- **eks**: provides cluster_security_group_id for ingress rule injection

### Key Configuration Settings

- **Instance**:
  - Type: `t3.nano`
  - Name pattern: `{env}-{region_abbv}-ssm-bastion`
  - Subnet: first kubernetes subnet

- **Security**:
  - No inbound ports opened; access is via SSM Session Manager only
  - Egress-only security group
  - Adds ingress rule to EKS cluster security group for API server communication

## Usage

```bash
cd infra/live/aws/platform/us-east-1/platform/ssm-bastion
terragrunt plan
terragrunt apply
```

## Dependencies on this Configuration

None. This is a leaf node in the deployment graph.

## Implementation Notes

Use `./scripts/eks-tunnel.sh` to establish an SSM tunnel and configure kubectl access to the EKS cluster. No direct SSH is available; all session access goes through SSM.
