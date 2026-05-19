# EKS Cluster - US East 1 (Platform)

## Overview

Deploys an Amazon EKS cluster (control plane only) in BYOCNI mode for the platform environment in us-east-1.

## Configuration Details

### Purpose

- Provisions the EKS control plane without a default CNI plugin (Cilium is deployed separately)
- Configures API endpoint access for both private and public connectivity
- Grants cluster admin access to the OrganizationAccountAccessRole IAM role
- Attaches EKS security groups from the networking module

### Dependencies

- **networking**: provides kubernetes subnet IDs for control plane ENI placement and the EKS security group ID

### Key Configuration Settings

- **Cluster**:
  - Name pattern: `{env}-{region_abbv}-eks`
  - CNI mode: BYOCNI (no default CNI installed)
  - Subnet placement: kubernetes subnets only

- **Endpoint Access**:
  - Private: enabled
  - Public: enabled
  - public_access_cidrs: `["0.0.0.0/0"]`

- **Access Entries**:
  - admin: `OrganizationAccountAccessRole` with `AmazonEKSClusterAdminPolicy`

## Usage

```bash
cd infra/live/aws/platform/us-east-1/platform/eks
terragrunt plan
terragrunt apply
```

## Dependencies on this Configuration

- **cilium**: consumes cluster endpoint, CA certificate, and cluster ID
- **node-groups**: consumes cluster ID
- **ssm-bastion**: consumes cluster security group ID
- **argocd**: consumes cluster connection details

## Implementation Notes

`public_access_cidrs = ["0.0.0.0/0"]` must be locked down to VPN/office/CI IP ranges before production workloads are deployed.
