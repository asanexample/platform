# Network configuration for Azure eastus region

locals {
  # VNet CIDR block for eastus
  address_space = ["10.17.0.0/23"]
  
  # Subnet configurations specific to eastus
  subnets = {
    "node" = {
      address_prefixes  = ["10.17.0.0/26"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.ContainerRegistry"]
    },
    "endpoint" = {
      address_prefixes  = ["10.17.0.80/28"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.Sql", "Microsoft.KeyVault"]
    }
  }
} 