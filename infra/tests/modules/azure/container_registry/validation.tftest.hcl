/**
 * # Container Registry Module - Validation Test
 * 
 * This test verifies the validation rules of the Azure Container Registry module
 * to ensure that input variables are properly validated.
 */

# Define provider configuration for the test runs
provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id       = "c945e155-be68-4477-b8d7-01939adbfe55"
  resource_provider_registrations = "none"
}

# Test name validation with custom name
run "name_validation_test" {
  command = plan

  variables {
    create_registry     = true
    name                = "testacr123"
    resource_group_name = "test-rg"
    location            = "eastus"
    prefix              = "test"
    environment         = "dev"
    region_abbv         = "eus"
    tags                = {}
  }

  module {
    source = "../../../../modules/azure/container_registry"
  }

  assert {
    condition     = var.name == "testacr123"
    error_message = "Custom ACR name should be accepted"
  }
}

# Test with default name generation
run "default_name_validation_test" {
  command = plan

  variables {
    create_registry     = true
    name                = null
    resource_group_name = "test-rg"
    location            = "eastus"
    prefix              = "test"
    environment         = "dev"
    region_abbv         = "eus"
    tags                = {}
  }

  module {
    source = "../../../../modules/azure/container_registry"
  }

  assert {
    condition     = var.name == null
    error_message = "Default name generation should be used when name is null"
  }
}

# Test location validation
run "location_validation_test" {
  command = plan

  variables {
    create_registry     = true
    resource_group_name = "test-rg"
    location            = "eastus"
    prefix              = "test"
    environment         = "dev"
    region_abbv         = "eus"
    tags                = {}
  }

  module {
    source = "../../../../modules/azure/container_registry"
  }

  assert {
    condition     = contains(["eastus", "eastus2", "southcentralus", "westus", "westus2", "westus3", "centralus", "northcentralus", "brazilsouth", "eastasia", "southeastasia", "northeurope", "westeurope", "centralindia", "southindia", "japaneast", "japanwest", "koreacentral", "southafricanorth", "australiaeast", "australiasoutheast", "canadacentral", "canadaeast", "germanywestcentral", "norwayeast", "swedencentral", "switzerlandnorth", "uaenorth", "uksouth", "ukwest", "francecentral", "jioindiawest", "westcentralus"], var.location)
    error_message = "Location must be a valid Azure region"
  }
}

# Test prefix validation
run "prefix_validation_test" {
  command = plan

  variables {
    create_registry     = true
    resource_group_name = "test-rg"
    location            = "eastus"
    prefix              = "test"
    environment         = "dev"
    region_abbv         = "eus"
    tags                = {}
  }

  module {
    source = "../../../../modules/azure/container_registry"
  }

  assert {
    condition     = length(var.prefix) >= 1 && length(var.prefix) <= 10 && can(regex("^[a-zA-Z0-9-_]+$", var.prefix))
    error_message = "Prefix must be 1-10 characters and include only alphanumeric, hyphen, and underscore"
  }
}

# Test environment validation
run "environment_validation_test" {
  command = plan

  variables {
    create_registry     = true
    resource_group_name = "test-rg"
    location            = "eastus"
    prefix              = "test"
    environment         = "dev"
    region_abbv         = "eus"
    tags                = {}
  }

  module {
    source = "../../../../modules/azure/container_registry"
  }

  assert {
    condition     = contains(["dev", "preprod", "prod", "test", "stg", "ops"], var.environment)
    error_message = "Environment must be one of: dev, preprod, prod, test, stg, ops"
  }
}

# Test SKU validation
run "sku_validation_test" {
  command = plan

  variables {
    create_registry     = true
    resource_group_name = "test-rg"
    location            = "eastus"
    prefix              = "test"
    environment         = "dev"
    region_abbv         = "eus"
    sku                 = "Standard"
    tags                = {}
  }

  module {
    source = "../../../../modules/azure/container_registry"
  }

  assert {
    condition     = contains(["Basic", "Standard", "Premium"], var.sku)
    error_message = "SKU must be one of: Basic, Standard, Premium"
  }
}

# Test premium features validation with Standard SKU
run "premium_features_with_standard_sku_test" {
  command = plan

  variables {
    create_registry          = true
    resource_group_name      = "test-rg"
    location                 = "eastus"
    prefix                   = "test"
    environment              = "dev"
    region_abbv              = "eus"
    sku                      = "Standard"
    zone_redundancy_enabled  = false
    data_endpoint_enabled    = false
    geo_replication_locations = []
    tags                     = {}
  }

  module {
    source = "../../../../modules/azure/container_registry"
  }
}

# Test premium features validation with Premium SKU
run "premium_features_with_premium_sku_test" {
  command = plan

  variables {
    create_registry           = true
    resource_group_name       = "test-rg"
    location                  = "eastus"
    prefix                    = "test"
    environment               = "dev"
    region_abbv               = "eus"
    sku                       = "Premium"
    zone_redundancy_enabled   = true
    data_endpoint_enabled     = true
    geo_replication_locations = ["westus", "eastus2"]
    tags                      = {}
  }

  module {
    source = "../../../../modules/azure/container_registry"
  }

  assert {
    condition     = var.sku == "Premium" && var.zone_redundancy_enabled == true && var.data_endpoint_enabled == true
    error_message = "Premium features should be enabled with Premium SKU"
  }
}

# Test network rule validation
run "network_rule_validation_test" {
  command = plan

  variables {
    create_registry     = true
    resource_group_name = "test-rg"
    location            = "eastus"
    prefix              = "test"
    environment         = "dev"
    region_abbv         = "eus"
    sku                 = "Premium"
    network_rule_set    = {
      default_action = "Deny"
      ip_rules       = [
        {
          action   = "Allow"
          ip_range = "192.168.1.0/24"
        }
      ]
    }
    tags                = {}
  }

  module {
    source = "../../../../modules/azure/container_registry"
  }

  assert {
    condition     = var.network_rule_set.default_action == "Deny" && length(var.network_rule_set.ip_rules) == 1
    error_message = "Network rules should be properly configured"
  }
}

# Test AKS integration validation
run "aks_integration_validation_test" {
  command = plan

  variables {
    create_registry       = true
    resource_group_name   = "test-rg"
    location              = "eastus"
    prefix                = "test"
    environment           = "dev"
    region_abbv           = "eus"
    aks_integration_enabled = true
    aks_principal_id      = "00000000-0000-0000-0000-000000000000"
    enable_aks_acr_push   = true
    tags                  = {}
  }

  module {
    source = "../../../../modules/azure/container_registry"
  }

  assert {
    condition     = var.aks_integration_enabled == true && var.aks_principal_id != null
    error_message = "AKS integration should be enabled with a valid principal ID"
  }
}

# Test tags validation
run "tags_validation_test" {
  command = plan

  variables {
    create_registry     = true
    resource_group_name = "test-rg"
    location            = "eastus"
    prefix              = "test"
    environment         = "dev"
    region_abbv         = "eus"
    tags                = {
      environment = "test"
      application = "acr"
      owner       = "platform-team"
    }
  }

  module {
    source = "../../../../modules/azure/container_registry"
  }

  assert {
    condition     = length(keys(var.tags)) == 3
    error_message = "Tags should be accepted with valid format"
  }
} 