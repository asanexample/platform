# Network configuration for Azure westus region based on allocations.csv

locals {
  # VNet CIDR block for westus region - from allocations.csv
  address_space = ["10.101.24.0/21"]
  
  # Subnet configurations for westus region with three availability zones
  # Each AZ has Kubernetes, Services, Endpoints, Transit, and Public subnets
  subnets = {
    # AZ 1 (westus-1) subnets
    "az1-kubernetes" = {
      address_prefixes  = ["10.101.24.0/26"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.ContainerRegistry"]
    },
    "az1-services" = {
      address_prefixes  = ["10.101.24.64/27"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.Sql"]
    },
    "az1-endpoints" = {
      address_prefixes  = ["10.101.24.96/28"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.Sql", "Microsoft.KeyVault"]
    },
    "az1-transit" = {
      address_prefixes  = ["10.101.24.128/29"]
      service_endpoints = ["Microsoft.Storage"]
    },
    "az1-public" = {
      address_prefixes  = ["10.101.24.112/28"]
      service_endpoints = ["Microsoft.Storage"]
    },
    
    # AZ 2 (westus-2) subnets
    "az2-kubernetes" = {
      address_prefixes  = ["10.101.25.0/26"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.ContainerRegistry"]
    },
    "az2-services" = {
      address_prefixes  = ["10.101.25.64/27"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.Sql"]
    },
    "az2-endpoints" = {
      address_prefixes  = ["10.101.25.96/28"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.Sql", "Microsoft.KeyVault"]
    },
    "az2-transit" = {
      address_prefixes  = ["10.101.25.128/29"]
      service_endpoints = ["Microsoft.Storage"]
    },
    "az2-public" = {
      address_prefixes  = ["10.101.25.112/28"]
      service_endpoints = ["Microsoft.Storage"]
    },
    
    # AZ 3 (westus-3) subnets
    "az3-kubernetes" = {
      address_prefixes  = ["10.101.26.0/26"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.ContainerRegistry"]
    },
    "az3-services" = {
      address_prefixes  = ["10.101.26.64/27"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.Sql"]
    },
    "az3-endpoints" = {
      address_prefixes  = ["10.101.26.96/28"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.Sql", "Microsoft.KeyVault"]
    },
    "az3-transit" = {
      address_prefixes  = ["10.101.26.128/29"]
      service_endpoints = ["Microsoft.Storage"]
    },
    "az3-public" = {
      address_prefixes  = ["10.101.26.112/28"]
      service_endpoints = ["Microsoft.Storage"]
    }
  }
} 