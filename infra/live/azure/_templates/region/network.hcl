# Network configuration for Azure __REGION__ region

locals {
  # VNet CIDR block for this region
  address_space = ["__CIDR_RANGE__"]
  
  # Subnet configurations for this region
  # These will be automatically generated based on the CIDR range
  # or populated from allocations.csv if available
  subnets = {
    # AZ 1 subnets
    "az1-node" = {
      address_prefixes  = [cidrsubnet(local.address_space[0], 2, 0)]  # 1/4 of the CIDR space
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.ContainerRegistry"]
    },
    "az1-services" = {
      address_prefixes  = [cidrsubnet(local.address_space[0], 3, 2)]  # 1/8 of the CIDR space
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.Sql"]
    },
    "az1-endpoints" = {
      address_prefixes  = [cidrsubnet(local.address_space[0], 4, 6)]  # 1/16 of the CIDR space
      service_endpoints = ["Microsoft.Storage", "Microsoft.Sql", "Microsoft.KeyVault"]
    },
    "az1-transit" = {
      address_prefixes  = [cidrsubnet(local.address_space[0], 5, 14)]  # 1/32 of the CIDR space
      service_endpoints = ["Microsoft.Storage"]
    },
    
    # AZ 2 subnets
    "az2-node" = {
      address_prefixes  = [cidrsubnet(local.address_space[0], 2, 1)]  # 1/4 of the CIDR space
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.ContainerRegistry"]
    },
    "az2-services" = {
      address_prefixes  = [cidrsubnet(local.address_space[0], 3, 3)]  # 1/8 of the CIDR space
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.Sql"]
    },
    "az2-endpoints" = {
      address_prefixes  = [cidrsubnet(local.address_space[0], 4, 7)]  # 1/16 of the CIDR space
      service_endpoints = ["Microsoft.Storage", "Microsoft.Sql", "Microsoft.KeyVault"]
    },
    "az2-transit" = {
      address_prefixes  = [cidrsubnet(local.address_space[0], 5, 15)]  # 1/32 of the CIDR space
      service_endpoints = ["Microsoft.Storage"]
    },
    
    # AZ 3 subnets
    "az3-node" = {
      address_prefixes  = [cidrsubnet(local.address_space[0], 2, 2)]  # 1/4 of the CIDR space
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.ContainerRegistry"]
    },
    "az3-services" = {
      address_prefixes  = [cidrsubnet(local.address_space[0], 3, 4)]  # 1/8 of the CIDR space
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.Sql"]
    },
    "az3-endpoints" = {
      address_prefixes  = [cidrsubnet(local.address_space[0], 4, 8)]  # 1/16 of the CIDR space
      service_endpoints = ["Microsoft.Storage", "Microsoft.Sql", "Microsoft.KeyVault"]
    },
    "az3-transit" = {
      address_prefixes  = [cidrsubnet(local.address_space[0], 5, 16)]  # 1/32 of the CIDR space
      service_endpoints = ["Microsoft.Storage"]
    }
  }
} 