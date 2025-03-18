# Network configuration for Azure northeurope region based on allocations.csv

locals {
  # VNet CIDR block for northeurope region
  address_space = ["10.101.64.0/20"]
  
  # Subnet configurations for northeurope region with three availability zones
  # Each AZ has Kubernetes, Services, Endpoints, and Transit subnets
  subnets = {
    # AZ 1 (northeuropea) subnets - using non-overlapping ranges
    "az1-kubernetes" = {
      address_prefixes  = ["10.101.64.0/24"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.ContainerRegistry"]
    },
    "az1-services" = {
      address_prefixes  = ["10.101.64.128/26"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.Sql"]
    },
    "az1-endpoints" = {
      address_prefixes  = ["10.101.64.192/27"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.Sql", "Microsoft.KeyVault"]
    },
    "az1-transit" = {
      address_prefixes  = ["10.101.64.224/28"]
      service_endpoints = ["Microsoft.Storage"]
    },
    
    # AZ 2 (northeuropeb) subnets - using non-overlapping ranges
    "az2-kubernetes" = {
      address_prefixes  = ["10.101.65.0/24"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.ContainerRegistry"]
    },
    "az2-services" = {
      address_prefixes  = ["10.101.65.128/26"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.Sql"]
    },
    "az2-endpoints" = {
      address_prefixes  = ["10.101.65.192/27"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.Sql", "Microsoft.KeyVault"]
    },
    "az2-transit" = {
      address_prefixes  = ["10.101.65.224/28"]
      service_endpoints = ["Microsoft.Storage"]
    },
    
    # AZ 3 (northeuropec) subnets - using non-overlapping ranges
    "az3-kubernetes" = {
      address_prefixes  = ["10.101.66.0/24"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.ContainerRegistry"]
    },
    "az3-services" = {
      address_prefixes  = ["10.101.66.128/26"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.Sql"]
    },
    "az3-endpoints" = {
      address_prefixes  = ["10.101.66.192/27"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.Sql", "Microsoft.KeyVault"]
    },
    "az3-transit" = {
      address_prefixes  = ["10.101.66.224/28"]
      service_endpoints = ["Microsoft.Storage"]
    }
  }
} 