# Network configuration for Azure eastus region based on allocations.csv

locals {
  # VNet CIDR block for eastus region
  address_space = ["10.101.0.0/20"]
  
  # Subnet configurations for eastus region with three availability zones
  # Each AZ has Kubernetes, Services, Endpoints, and Transit subnets
  subnets = {
    # AZ 1 (eastusa) subnets - using non-overlapping ranges
    "az1-kubernetes" = {
      address_prefixes  = ["10.101.0.0/24"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.ContainerRegistry"]
    },
    "az1-services" = {
      address_prefixes  = ["10.101.0.128/26"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.Sql"]
    },
    "az1-endpoints" = {
      address_prefixes  = ["10.101.0.192/27"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.Sql", "Microsoft.KeyVault"]
    },
    "az1-transit" = {
      address_prefixes  = ["10.101.0.224/28"]
      service_endpoints = ["Microsoft.Storage"]
    },
    
    # AZ 2 (eastusb) subnets - using non-overlapping ranges
    "az2-kubernetes" = {
      address_prefixes  = ["10.101.1.0/24"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.ContainerRegistry"]
    },
    "az2-services" = {
      address_prefixes  = ["10.101.1.128/26"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.Sql"]
    },
    "az2-endpoints" = {
      address_prefixes  = ["10.101.1.192/27"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.Sql", "Microsoft.KeyVault"]
    },
    "az2-transit" = {
      address_prefixes  = ["10.101.1.224/28"]
      service_endpoints = ["Microsoft.Storage"]
    },
    
    # AZ 3 (eastusc) subnets - using non-overlapping ranges
    "az3-kubernetes" = {
      address_prefixes  = ["10.101.2.0/24"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.ContainerRegistry"]
    },
    "az3-services" = {
      address_prefixes  = ["10.101.2.128/26"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.Sql"]
    },
    "az3-endpoints" = {
      address_prefixes  = ["10.101.2.192/27"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.Sql", "Microsoft.KeyVault"]
    },
    "az3-transit" = {
      address_prefixes  = ["10.101.2.224/28"]
      service_endpoints = ["Microsoft.Storage"]
    }
  }
} 