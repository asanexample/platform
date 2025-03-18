# Network Topology and CIDR Allocation

This document outlines our network topology and CIDR allocation strategy across multiple cloud providers based on the comprehensive allocations defined in `allocations.csv`.

## Multi-Cloud CIDR Allocation

Our network addressing follows a hierarchical approach that provides clear IP address allocation across different cloud providers and environments:

| Account | Cloud Provider | CIDR Range | Purpose |
|---------|---------------|------------|---------|
| innovation-operations | AWS | 10.100.0.0/16 | Primary VPC for AWS environments |
| innovation-operations | Azure | 10.101.0.0/16 | Primary VNet for Azure environments |

## Regional Allocation Strategy

Each region follows a consistent pattern with CIDR blocks allocated per region:

1. Each **region** is allocated a `/20` CIDR block within the cloud provider's address space
2. Within each region, **availability zones** each receive a `/24` CIDR block
3. Within each availability zone, specialized **subnet types** are created with non-overlapping CIDR ranges

| Subnet Role | CIDR Size | IP Range Example | IPs Available | Purpose |
|-------------|-----------|------------------|---------------|---------|
| Kubernetes | /24 | 10.101.0.0/24 | 254 | Kubernetes node networking |
| Services | /26 | 10.101.0.128/26 | 62 | Application and service networking |
| Endpoints | /27 | 10.101.0.192/27 | 30 | Private endpoints and service connections |
| Transit | /28 | 10.101.0.224/28 | 14 | Transit gateways and network connections |

## AWS Region Allocations

| Region | Region CIDR | AZs |
|--------|-------------|-----|
| us-east-1 | 10.100.0.0/20 | us-east-1a, us-east-1b, us-east-1c |
| us-east-2 | 10.100.16.0/20 | us-east-2a, us-east-2b, us-east-2c |
| us-west-1 | 10.100.32.0/20 | us-west-1a, us-west-1b |
| us-west-2 | 10.100.48.0/20 | us-west-2a, us-west-2b, us-west-2c |
| eu-west-1 | 10.100.64.0/20 | eu-west-1a, eu-west-1b, eu-west-1c |
| eu-west-2 | 10.100.80.0/20 | eu-west-2a, eu-west-2b, eu-west-2c |
| eu-west-3 | 10.100.96.0/20 | eu-west-3a, eu-west-3b, eu-west-3c |
| eu-central-1 | 10.100.112.0/20 | eu-central-1a, eu-central-1b, eu-central-1c |
| eu-north-1 | 10.100.128.0/20 | eu-north-1a, eu-north-1b, eu-north-1c |
| ap-northeast-1 | 10.100.144.0/20 | ap-northeast-1a, ap-northeast-1b, ap-northeast-1c |
| ap-southeast-1 | 10.100.160.0/20 | ap-southeast-1a, ap-southeast-1b, ap-southeast-1c |
| ap-southeast-2 | 10.100.176.0/20 | ap-southeast-2a, ap-southeast-2b, ap-southeast-2c |
| ap-south-1 | 10.100.192.0/20 | ap-south-1a, ap-south-1b, ap-south-1c |
| sa-east-1 | 10.100.208.0/20 | sa-east-1a, sa-east-1b, sa-east-1c |
| ca-central-1 | 10.100.224.0/20 | ca-central-1a, ca-central-1b, ca-central-1c |
| af-south-1 | 10.100.240.0/20 | af-south-1a, af-south-1b, af-south-1c |

## Azure Region Allocations

| Region | Region CIDR | AZs |
|--------|-------------|-----|
| eastus | 10.101.0.0/20 | eastusa, eastusb, eastusc |
| eastus2 | 10.101.16.0/20 | eastus2a, eastus2b, eastus2c |
| westus | 10.101.32.0/20 | westusa, westusb, westusc |
| westus2 | 10.101.48.0/20 | westus2a, westus2b, westus2c |
| northeurope | 10.101.64.0/20 | northeuropea, northeuropeb, northeuropec |
| westeurope | 10.101.80.0/20 | westeuropea, westeuropeb, westeuropec |

## Subnet Purpose Definitions

1. **Kubernetes Subnets** (/24): These subnets host Kubernetes node VMs and are sized to accommodate multiple node pools. They use the first half of each AZ's address space (e.g., 10.101.0.0/24).

2. **Services Subnets** (/26): Used for dedicated services that run outside of Kubernetes, such as databases, caches, and application servers. They use the third quarter of each AZ's address space (e.g., 10.101.0.128/26).

3. **Endpoints Subnets** (/27): Dedicated to private endpoints and service connections to PaaS services. They use a portion of the last quarter of each AZ's address space (e.g., 10.101.0.192/27).

4. **Transit Subnets** (/28): Used for connectivity between networks, including transit gateways, VPN endpoints, and ExpressRoute connections. They use the final portion of each AZ's address space (e.g., 10.101.0.224/28).

## Subnet Allocation Within Each AZ

For each AZ, we follow this pattern to ensure no CIDR overlaps:

```
AZ CIDR: 10.101.X.0/24 (where X is the AZ identifier)

- Kubernetes: 10.101.X.0/24    (uses the full AZ space for Kubernetes)
- Services:   10.101.X.128/26  (uses the second half's first half)
- Endpoints:  10.101.X.192/27  (uses the second half's second half's first half)
- Transit:    10.101.X.224/28  (uses the second half's second half's second half)
```

This approach gives us non-overlapping subnet ranges within each AZ while still maintaining the hierarchy and logical organization.

## Implementation Notes

1. All network security groups, firewalls, and ACLs should leverage the hierarchical structure
2. New regions should follow this allocation pattern
3. Pod and service CIDR blocks for Kubernetes should be isolated from VPC/VNet CIDR ranges
4. All subnet CIDR blocks within an AZ must be non-overlapping to comply with Azure networking requirements

## Governance

The master source of truth for IP allocation is maintained in `allocations.csv`. This document serves as a guide and explanation, but the CSV should be consulted for the most current and specific allocations. 