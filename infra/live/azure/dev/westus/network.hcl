# Network configuration for Azure westus region

locals {
  # VNet CIDR block for westus
  address_space = ["10.17.2.0/23"]
  
  # Subnet configurations specific to westus
  subnets = {
    "az1-node-subnet" = {
      address_prefixes  = ["10.17.2.0/26"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.ContainerRegistry"]
    },
    "az1-endpoint-subnet" = {
      address_prefixes  = ["10.17.2.80/28"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.Sql", "Microsoft.KeyVault"]
    }
  }
} 