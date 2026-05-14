# Terragrunt configuration for Azure storage in westus region

include "base" {
  path   = find_in_parent_folders("azure/_base.hcl")
  expose = true
}

# Include the root terragrunt.hcl configuration
include "root" {
  path = find_in_parent_folders()
}

# Include the common configuration for Storage
include "storage_common" {
  path = find_in_parent_folders("azure/_envcommon/storage.hcl")
}

# Add data dependency for current client identity
dependency "client_config" {
  config_path = "../client_config"

  # Mock outputs for plan and validation
  mock_outputs = {
    client_id       = "00000000-0000-0000-0000-000000000000"
    object_id       = "00000000-0000-0000-0000-000000000000"
    subscription_id = "00000000-0000-0000-0000-000000000000"
    tenant_id       = "00000000-0000-0000-0000-000000000000"
  }
}

# Set dependencies for this module (these will merge with the common inputs)
dependency "naming" {
  config_path = "../naming"

  # Mock outputs for plan and validation
  mock_outputs = {
    storage_account = "mocksa"
    private_endpoint = "mock-pe"
  }
}

dependency "resource_group" {
  config_path = "../resource_group"

  # Mock outputs for plan and validation
  mock_outputs = {
    name = "mock-rg"
    location = include.base.locals.region
  }
}

dependency "networking" {
  config_path = "../networking"

  # Mock outputs for plan and validation
  mock_outputs = {
    subnet_ids = {
      "az1-endpoints" = "/subscriptions/mock-id/resourceGroups/mock-rg/providers/Microsoft.Network/virtualNetworks/mock-vnet/subnets/az1-endpoints"
    }
  }
}

dependency "dns" {
  config_path = "../dns"

  # Mock outputs for plan and validation
  mock_outputs = {
    private_dns_zone_ids = {
      "blob" = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
    }
  }
}

# Specify inputs specific to this module (these will merge with the common inputs)
inputs = {
  create = true

  # Environment variables
  environment = include.base.locals.env
  workload = include.base.locals.workload
  region_abbv = include.base.locals.region_abbv

  # Resource group
  resource_group_name = dependency.resource_group.outputs.name
  location = dependency.resource_group.outputs.location

  # Storage account name
  name = dependency.naming.outputs.storage_account

  # Storage account configuration
  account_tier = "Standard"
  account_replication_type = "LRS"

  # Enable public network access
  public_network_access_enabled = true

  # Network rules
  network_rules = {
    default_action = "Allow"
    bypass = ["AzureServices"]
    virtual_network_subnet_ids = [
      dependency.networking.outputs.subnet_ids["az1-endpoints"]
    ]
    # Uncomment and add specific IPs if needed in the future
    # ip_rules = ["1.2.3.4", "5.6.7.8"]
  }

  # Private endpoint configuration
  private_endpoint = {
    create                       = true
    name                         = dependency.naming.outputs.private_endpoint
    subnet_id                    = dependency.networking.outputs.subnet_ids["az1-endpoints"]
    subresource_names            = ["blob"]
    private_service_connection_name = "service-connection"
    private_dns_zone_ids         = [dependency.dns.outputs.private_dns_zone_ids["blob"]]
  }

  # Containers
  containers = {
    "data" = {
      name = "data"
      container_access_type = "private"
    }
    "logs" = {
      name = "logs"
      container_access_type = "private"
    }
  }

  # Lifecycle management for logs
  lifecycle_rules = [
    {
      name    = "logs-lifecycle"
      enabled = true
      prefix_match = ["logs/"]

      # Move logs to cool tier after 30 days
      tier_to_cool_action = {
        days_after_modification_greater_than = 30
      }

      # Move logs to archive tier after 90 days
      tier_to_archive_action = {
        days_after_modification_greater_than = 90
      }

      # Delete logs after 2 years (730 days)
      delete_action = {
        days_after_modification_greater_than = 730
      }
    }
  ]

  # Security settings
  allow_nested_items_to_be_public = false
  blob_public_access_enabled = false

  # Enable access keys for provider authentication
  shared_access_key_enabled = true

  # Role assignments removed - these are now managed by the storage_roles module
  # to maintain separation of concerns and follow the single responsibility principle

  # Tags
  tags = include.base.locals.tags
}
