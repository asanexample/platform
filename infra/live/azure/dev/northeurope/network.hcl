# Network configuration for Azure northeurope region based on allocations.csv

locals {
  # VNet CIDR block for northeurope region
  address_space = ["10.101.72.0/21"]
  
  # Subnet configurations for northeurope region with three availability zones
  # Each AZ has Kubernetes, Services, Endpoints, and Transit subnets
  subnets = {
    # AZ 1 (northeurope-1) subnets
    "az1-kubernetes" = {
      address_prefixes  = ["10.101.72.0/26"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.ContainerRegistry"]
    },
    "az1-services" = {
      address_prefixes  = ["10.101.72.64/27"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.Sql"]
    },
    "az1-endpoints" = {
      address_prefixes  = ["10.101.72.96/28"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.Sql", "Microsoft.KeyVault"]
    },
    "az1-transit" = {
      address_prefixes  = ["10.101.72.112/29"]
      service_endpoints = ["Microsoft.Storage"]
    },
    
    # AZ 2 (northeurope-2) subnets
    "az2-kubernetes" = {
      address_prefixes  = ["10.101.73.0/26"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.ContainerRegistry"]
    },
    "az2-services" = {
      address_prefixes  = ["10.101.73.64/27"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.Sql"]
    },
    "az2-endpoints" = {
      address_prefixes  = ["10.101.73.96/28"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.Sql", "Microsoft.KeyVault"]
    },
    "az2-transit" = {
      address_prefixes  = ["10.101.73.112/29"]
      service_endpoints = ["Microsoft.Storage"]
    },
    
    # AZ 3 (northeurope-3) subnets
    "az3-kubernetes" = {
      address_prefixes  = ["10.101.74.0/26"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.ContainerRegistry"]
    },
    "az3-services" = {
      address_prefixes  = ["10.101.74.64/27"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.Sql"]
    },
    "az3-endpoints" = {
      address_prefixes  = ["10.101.74.96/28"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.Sql", "Microsoft.KeyVault"]
    },
    "az3-transit" = {
      address_prefixes  = ["10.101.74.112/29"]
      service_endpoints = ["Microsoft.Storage"]
    }
  }
} 