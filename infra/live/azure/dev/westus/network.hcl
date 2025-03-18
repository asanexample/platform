# Network configuration for Azure westus region based on allocations.csv

locals {
  # VNet CIDR block for westus region
  address_space = ["10.101.32.0/20"]
  
  # Subnet configurations for westus region with three availability zones
  # Each AZ has Kubernetes, Services, Endpoints, and Transit subnets
  subnets = {
    # AZ 1 (westusa) subnets - using non-overlapping ranges
    "az1-kubernetes" = {
      address_prefixes  = ["10.101.32.0/24"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.ContainerRegistry"]
    },
    "az1-services" = {
      address_prefixes  = ["10.101.32.128/26"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.Sql"]
    },
    "az1-endpoints" = {
      address_prefixes  = ["10.101.32.192/27"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.Sql", "Microsoft.KeyVault"]
    },
    "az1-transit" = {
      address_prefixes  = ["10.101.32.224/28"]
      service_endpoints = ["Microsoft.Storage"]
    },
    
    # AZ 2 (westusb) subnets - using non-overlapping ranges
    "az2-kubernetes" = {
      address_prefixes  = ["10.101.33.0/24"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.ContainerRegistry"]
    },
    "az2-services" = {
      address_prefixes  = ["10.101.33.128/26"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.Sql"]
    },
    "az2-endpoints" = {
      address_prefixes  = ["10.101.33.192/27"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.Sql", "Microsoft.KeyVault"]
    },
    "az2-transit" = {
      address_prefixes  = ["10.101.33.224/28"]
      service_endpoints = ["Microsoft.Storage"]
    },
    
    # AZ 3 (westusc) subnets - using non-overlapping ranges
    "az3-kubernetes" = {
      address_prefixes  = ["10.101.34.0/24"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.ContainerRegistry"]
    },
    "az3-services" = {
      address_prefixes  = ["10.101.34.128/26"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.Sql"]
    },
    "az3-endpoints" = {
      address_prefixes  = ["10.101.34.192/27"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.Sql", "Microsoft.KeyVault"]
    },
    "az3-transit" = {
      address_prefixes  = ["10.101.34.224/28"]
      service_endpoints = ["Microsoft.Storage"]
    }
  }
} 