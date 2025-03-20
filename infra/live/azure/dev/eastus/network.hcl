# Network configuration for azure eastus region based on allocations.csv

locals {
  # VNet CIDR block for eastus region
  address_space = ["10.101.0.0/21"]
  
  # Subnet configurations for eastus region with three availability zones
  # Each AZ has Kubernetes, Services, Endpoints, and Transit subnets
  subnets = {
    # AZ 1 (eastus-1) subnets
    "az1-kubernetes" = {
      address_prefixes  = ["10.101.0.0/24"]  # Increased from /26 to /24 for more IPs
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.ContainerRegistry"]
    },
    "az1-services" = {
      address_prefixes  = ["10.101.1.0/27"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.Sql"]
    },
    "az1-endpoints" = {
      address_prefixes  = ["10.101.1.32/28"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.Sql", "Microsoft.KeyVault"]
    },
    "az1-transit" = {
      address_prefixes  = ["10.101.1.48/29"]
      service_endpoints = ["Microsoft.Storage"]
    },
    
    # AZ 2 (eastus-2) subnets
    "az2-kubernetes" = {
      address_prefixes  = ["10.101.2.0/24"]  # Increased from /26 to /24 for more IPs
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.ContainerRegistry"]
    },
    "az2-services" = {
      address_prefixes  = ["10.101.3.0/27"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.Sql"]
    },
    "az2-endpoints" = {
      address_prefixes  = ["10.101.3.32/28"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.Sql", "Microsoft.KeyVault"]
    },
    "az2-transit" = {
      address_prefixes  = ["10.101.3.48/29"]
      service_endpoints = ["Microsoft.Storage"]
    },
    
    # AZ 3 (eastus-3) subnets
    "az3-kubernetes" = {
      address_prefixes  = ["10.101.4.0/24"]  # Increased from /26 to /24 for more IPs
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.ContainerRegistry"]
    },
    "az3-services" = {
      address_prefixes  = ["10.101.5.0/27"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.Sql"]
    },
    "az3-endpoints" = {
      address_prefixes  = ["10.101.5.32/28"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.Sql", "Microsoft.KeyVault"]
    },
    "az3-transit" = {
      address_prefixes  = ["10.101.5.48/29"]
      service_endpoints = ["Microsoft.Storage"]
    }
  }
}
