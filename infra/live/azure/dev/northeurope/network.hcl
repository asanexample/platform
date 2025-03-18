# Network configuration for Azure northeurope region

locals {
  # VNet CIDR block for northeurope
  address_space = ["10.17.4.0/23"]
  
  # Subnet configurations specific to northeurope
  subnets = {
    "az1-node-subnet" = {
      address_prefixes  = ["10.17.4.0/26"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.ContainerRegistry"]
    },
    "az1-endpoint-subnet" = {
      address_prefixes  = ["10.17.4.80/28"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.Sql", "Microsoft.KeyVault"]
    }
  }
} 