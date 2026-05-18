# Network configuration for Azure eastus region based on allocations.csv

locals {
  # VNet CIDR block for eastus region - from allocations.csv
  address_space = ["10.104.0.0/16"]

  # Subnet configurations for eastus region with three availability zones
  # Each AZ has Kubernetes, Services, Endpoints, Firewall, Transit, and Public subnets
  subnets = {
    # AZ 1 (eastus-1) subnets
    "az1-kubernetes" = {
      address_prefixes  = ["10.104.0.0/26"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.ContainerRegistry"]
    },
    "az1-services" = {
      address_prefixes  = ["10.104.0.192/27"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.Sql"]
    },
    "az1-endpoints" = {
      address_prefixes  = ["10.104.0.64/26"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.Sql", "Microsoft.KeyVault"]
    },
    "AzureFirewallSubnet" = {
      address_prefixes  = ["10.104.0.128/26"]
      service_endpoints = ["Microsoft.Storage"]
    },
    "az1-transit" = {
      address_prefixes  = ["10.104.0.240/29"]
      service_endpoints = ["Microsoft.Storage"]
    },
    "az1-public" = {
      address_prefixes  = ["10.104.0.224/28"]
      service_endpoints = ["Microsoft.Storage"]
    },

    # AZ 2 (eastus-2) subnets
    "az2-kubernetes" = {
      address_prefixes  = ["10.104.1.0/26"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.ContainerRegistry"]
    },
    "az2-services" = {
      address_prefixes  = ["10.104.1.192/27"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.Sql"]
    },
    "az2-endpoints" = {
      address_prefixes  = ["10.104.1.64/26"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.Sql", "Microsoft.KeyVault"]
    },
    "az2-reserved" = {
      address_prefixes  = ["10.104.1.128/26"]
      service_endpoints = ["Microsoft.Storage"]
    },
    "az2-transit" = {
      address_prefixes  = ["10.104.1.240/29"]
      service_endpoints = ["Microsoft.Storage"]
    },
    "az2-public" = {
      address_prefixes  = ["10.104.1.224/28"]
      service_endpoints = ["Microsoft.Storage"]
    },

    # AZ 3 (eastus-3) subnets
    "az3-kubernetes" = {
      address_prefixes  = ["10.104.2.0/26"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.ContainerRegistry"]
    },
    "az3-services" = {
      address_prefixes  = ["10.104.2.192/27"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.Sql"]
    },
    "az3-endpoints" = {
      address_prefixes  = ["10.104.2.64/26"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.Sql", "Microsoft.KeyVault"]
    },
    "az3-reserved" = {
      address_prefixes  = ["10.104.2.128/26"]
      service_endpoints = ["Microsoft.Storage"]
    },
    "az3-transit" = {
      address_prefixes  = ["10.104.2.240/29"]
      service_endpoints = ["Microsoft.Storage"]
    },
    "az3-public" = {
      address_prefixes  = ["10.104.2.224/28"]
      service_endpoints = ["Microsoft.Storage"]
    }
  }
} 