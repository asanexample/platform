# Multi-Region Deployment Guide

This document provides guidance for deploying infrastructure across multiple regions, ensuring consistency, reliability, and fault tolerance.

## Overview

The multi-cloud platform supports deployment across multiple regions to achieve:

1. **Geographic Distribution**: Placing workloads closer to users
2. **Disaster Recovery**: Protection against regional outages
3. **High Availability**: Increased availability through redundancy
4. **Compliance**: Meeting data residency requirements

## Deployment Models

The platform supports three multi-region deployment models:

### 1. Active-Active

- **Configuration**: Full workload deployment in multiple regions
- **Data**: Data synchronization between regions (typically with eventual consistency)
- **Traffic**: Load balanced across all regions, often via global load balancers
- **Failover**: Automatic, with minimal user impact
- **Use Case**: Global applications requiring high availability and low latency for users in different regions

### 2. Active-Passive

- **Configuration**: Primary region active, secondary region(s) on standby
- **Data**: Regular data replication from primary to secondary
- **Traffic**: Directed to primary region during normal operation
- **Failover**: Manual or automated failover to secondary region during primary outage
- **Use Case**: Applications with strict data consistency requirements or cost constraints

### 3. Hybrid

- **Configuration**: Core services replicated across regions, specialized workloads in specific regions
- **Data**: Shared data replicated across regions, region-specific data local
- **Traffic**: Routed based on service location and user proximity
- **Failover**: Partial automatic failover for replicated services
- **Use Case**: Applications with global core functionality and region-specific requirements

## Implementation Strategy

### Region Selection

Select regions based on:

1. **User Distribution**: Choose regions close to user concentrations
2. **Regulatory Requirements**: Consider data residency requirements
3. **Service Availability**: Ensure required services are available in selected regions
4. **Disaster Recovery**: Select geographically diverse regions for DR purposes
5. **Cost**: Consider regional price differences

### Resource Deployment

#### Common Infrastructure

Deploy shared resources using Terragrunt:

```
infra/
└── live/
    └── azure/
        ├── global/            # Global resources
        │   └── dns/           # Global DNS configuration
        ├── dev/               # Development environment
        │   ├── eastus/        # East US region
        │   │   ├── networking/
        │   │   └── aks/
        │   └── westus/        # West US region
        │       ├── networking/
        │       └── aks/
        └── prod/              # Production environment
            ├── eastus/        # East US region
            │   ├── networking/
            │   └── aks/
            └── westus/        # West US region
                ├── networking/
                └── aks/
```

#### Terragrunt Configuration

Use Terragrunt's inheritance to maintain consistency across regions:

```hcl
# _envcommon/networking.hcl
inputs = {
  common_tags = {
    Environment = "${local.environment}"
    ManagedBy   = "Terragrunt"
  }
  
  # Common network settings
  address_space_prefix = "10.${local.env_network_prefix}.${local.region_network_prefix}"
}

# live/azure/dev/eastus/networking/terragrunt.hcl
include "root" {
  path = find_in_parent_folders()
}

include "common" {
  path = "${dirname(find_in_parent_folders())}/_envcommon/networking.hcl"
}

locals {
  region_network_prefix = "8"  # East US dev uses 10.8.0.0/16
}

inputs = {
  location = "eastus"
  region_abbv = "eus"
}

# live/azure/dev/westus/networking/terragrunt.hcl
include "root" {
  path = find_in_parent_folders()
}

include "common" {
  path = "${dirname(find_in_parent_folders())}/_envcommon/networking.hcl"
}

locals {
  region_network_prefix = "9"  # West US dev uses 10.9.0.0/16
}

inputs = {
  location = "westus"
  region_abbv = "wus"
}
```

### Inter-Region Connectivity

For environments requiring connectivity between regions:

1. **VNet Peering**: Configure Global VNet Peering between regional VNets
2. **Traffic Manager/Front Door**: Use for global load balancing and failover
3. **Private Endpoints**: Configure region-specific private endpoints
4. **Cosmos DB/SQL**: Configure multi-region databases with appropriate consistency levels

```hcl
# Example of establishing global VNet peering
module "vnet_peering" {
  source = "../../modules/azure/vnet_peering"
  
  vnet_1_name                = "vip-vnet-dev-eus-main"
  vnet_1_id                  = dependency.eastus_networking.outputs.vnet_id
  vnet_1_resource_group_name = dependency.eastus_networking.outputs.resource_group_name
  
  vnet_2_name                = "vip-vnet-dev-wus-main"
  vnet_2_id                  = dependency.westus_networking.outputs.vnet_id
  vnet_2_resource_group_name = dependency.westus_networking.outputs.resource_group_name
  
  allow_forwarded_traffic  = true
  allow_gateway_transit    = false
  use_remote_gateways      = false
}
```

### Global Traffic Distribution

For distributing traffic across regions:

```hcl
# Example of Azure Front Door configuration
module "front_door" {
  source = "../../modules/azure/front_door"
  
  name                = "vip-fd-dev-global"
  resource_group_name = dependency.global_rg.outputs.resource_group_name
  
  routing_rules = [
    {
      name               = "default"
      accepted_protocols = ["Http", "Https"]
      patterns_to_match  = ["/*"]
      frontend_endpoints = ["frontend"]
      
      forwarding_configuration = {
        forwarding_protocol = "HttpsOnly"
        backend_pool_name   = "backends"
      }
    }
  ]
  
  backend_pools = [
    {
      name = "backends"
      backends = [
        {
          host            = dependency.eastus_k8s.outputs.ingress_hostname
          address         = dependency.eastus_k8s.outputs.ingress_ip
          http_port       = 80
          https_port      = 443
          weight          = 50
          priority        = 1
          enabled         = true
        },
        {
          host            = dependency.westus_k8s.outputs.ingress_hostname
          address         = dependency.westus_k8s.outputs.ingress_ip
          http_port       = 80
          https_port      = 443
          weight          = 50
          priority        = 1
          enabled         = true
        }
      ]
      
      load_balancing_settings = {
        sample_size                     = 4
        successful_samples_required     = 2
        additional_latency_milliseconds = 0
      }
      
      health_probe_settings = {
        path                = "/healthz"
        protocol            = "Https"
        interval_in_seconds = 30
      }
    }
  ]
}
```

## Data Replication Strategies

### Storage Account Replication

Configure geo-redundant storage for critical data:

```hcl
module "storage" {
  source = "../../modules/azure/storage_account"
  
  name                = module.naming.storage_account
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  
  # GRS for production, LRS for development
  account_replication_type = var.environment == "prod" ? "GRS" : "LRS"
  
  # Enable zone redundancy for production
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  enable_https_traffic_only = true
}
```

### Database Replication

For Cosmos DB with global distribution:

```hcl
resource "azurerm_cosmosdb_account" "db" {
  name                = "vip-cosmos-${var.stage}-global"
  location            = var.primary_location
  resource_group_name = azurerm_resource_group.this.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"
  
  enable_automatic_failover = true
  
  capabilities {
    name = "EnableServerless"
  }
  
  consistency_policy {
    consistency_level       = "Session"
    max_interval_in_seconds = 5
    max_staleness_prefix    = 100
  }
  
  geo_location {
    location          = var.primary_location
    failover_priority = 0
  }
  
  geo_location {
    location          = var.secondary_location
    failover_priority = 1
  }
}
```

## Disaster Recovery

For full disaster recovery configurations:

1. **RPO/RTO Objectives**: Define Recovery Point Objective and Recovery Time Objective for each application
2. **Backup Strategy**: Configure automated backups with appropriate retention periods
3. **Failover Testing**: Regularly test failover procedures
4. **Runbooks**: Document step-by-step failover and failback procedures

## Testing and Validation

Before deployment:

1. **Test in Lower Environments**: Deploy multi-region configuration in development first
2. **Connectivity Testing**: Verify connectivity between regions
3. **Failover Testing**: Simulate primary region failure and validate failover
4. **Performance Testing**: Measure latency and throughput across regions

## CIDR Allocation

- Refer to the CIDR allocation strategy in `infra/docs/cidr-allocation.md`
- Ensure non-overlapping IP ranges between regions

## Monitoring and Observability

For multi-region deployments:

1. **Global Dashboards**: Configure dashboards showing metrics across all regions
2. **Cross-Region Alerts**: Set up alerts for connectivity or replication issues
3. **Latency Monitoring**: Monitor inter-region network latency
4. **Health Checks**: Implement health checks for all regional endpoints

## Cost Optimization

To control costs in multi-region deployments:

1. **Active-Passive for Dev/Test**: Use active-passive model in non-production environments
2. **Right-sizing**: Size resources appropriately for each region based on expected load
3. **Reserved Instances**: Use reserved instances for committed resources in each region
4. **Cost Allocation**: Tag resources properly to track costs by region

## Deployment Process

1. **Global Resources First**: Deploy global/shared resources first
2. **Primary Region**: Deploy complete primary region infrastructure
3. **Secondary Regions**: Deploy secondary region infrastructure
4. **Inter-Region Configuration**: Configure connectivity and replication
5. **Validation**: Verify functionality across all regions

## Security Considerations

1. **Region-Specific Compliance**: Ensure compliance with region-specific regulations
2. **Key Vault Replication**: Replicate secrets and keys across regions
3. **Network Security**: Configure NSGs and firewalls in each region
4. **Identity Management**: Ensure consistent RBAC across regions

## Implementation Checklist

- [ ] Select appropriate regions based on requirements
- [ ] Configure Terragrunt for multi-region deployment
- [ ] Set up non-overlapping CIDR ranges for each region
- [ ] Deploy networking infrastructure in each region
- [ ] Configure inter-region connectivity
- [ ] Deploy regional resources (AKS, storage, etc.)
- [ ] Configure data replication between regions
- [ ] Set up global traffic distribution
- [ ] Implement monitoring and alerting
- [ ] Test failover procedures
- [ ] Document operational procedures

## References

- [Azure Multi-Region Design Patterns](https://learn.microsoft.com/en-us/azure/architecture/reference-architectures/app-service-web-app/multi-region)
- [CIDR Allocation Strategy](cidr-allocation.md)
- [Network Topology](network-topology.md) 