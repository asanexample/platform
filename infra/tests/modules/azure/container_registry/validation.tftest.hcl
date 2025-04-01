/**
 * # Azure Container Registry Module - Validation Tests
 * 
 * This file contains tests to verify that variable validations work correctly
 * in the container_registry module. It ensures proper error messages are 
 * generated for invalid inputs.
 */

# Variables needed for testing
variables {
  subscription_id = ""
  tenant_id       = ""

  # Default values for most tests
  resource_group_name = "test-rg"
  location            = "eastus"
  prefix              = "test"
  environment         = "dev"
  region_abbv         = "eus"
  create_registry     = true
  sku                 = "Standard"
}

# Provider configuration
provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id       = "c945e155-be68-4477-b8d7-01939adbfe55"
}

# Test name validation
run "invalid_name_format" {
  command = plan
  variables {
    name = "invalid@name"
  }

  module {
    source = "../../../../modules/azure/container_registry"
  }
}

# Test name minimum length validation
run "invalid_name_length_too_short" {
  command = plan
  variables {
    name = "acr"
  }

  module {
    source = "../../../../modules/azure/container_registry"
  }
}

# Test resource group name validation
run "invalid_resource_group_name" {
  command = plan
  variables {
    resource_group_name = "invalid*resource*group"
  }

  module {
    source = "../../../../modules/azure/container_registry"
  }
}

# Test location validation
run "invalid_location" {
  command = plan
  variables {
    location = "invalid-location"
  }

  module {
    source = "../../../../modules/azure/container_registry"
  }
}

# Test prefix validation
run "invalid_prefix" {
  command = plan
  variables {
    prefix = "invalid@prefix"
  }

  module {
    source = "../../../../modules/azure/container_registry"
  }
}

# Test prefix length validation
run "invalid_prefix_length" {
  command = plan
  variables {
    prefix = "thisPrefixIsTooLong"
  }

  module {
    source = "../../../../modules/azure/container_registry"
  }
}

# Test environment validation
run "invalid_environment" {
  command = plan
  variables {
    environment = "invalid-env"
  }

  module {
    source = "../../../../modules/azure/container_registry"
  }
}

# Test region_abbv validation
run "invalid_region_abbv" {
  command = plan
  variables {
    region_abbv = "EASTUS"
  }

  module {
    source = "../../../../modules/azure/container_registry"
  }
}

# Test SKU validation
run "invalid_sku" {
  command = plan
  variables {
    sku = "InvalidSku"
  }

  module {
    source = "../../../../modules/azure/container_registry"
  }
}

# Test geo-replication locations validation
run "invalid_geo_replication_location" {
  command = plan
  variables {
    sku                       = "Premium"
    geo_replication_locations = ["eastus", "invalid-location"]
  }

  module {
    source = "../../../../modules/azure/container_registry"
  }
}

# Test network rule set validation - default action
run "invalid_network_rule_default_action" {
  command = plan
  variables {
    sku = "Premium"
    network_rule_set = {
      default_action = "InvalidAction"
      ip_rules       = []
    }
  }

  module {
    source = "../../../../modules/azure/container_registry"
  }
}

# Test network rule set validation - IP rule format
run "invalid_network_rule_ip_format" {
  command = plan
  variables {
    sku = "Premium"
    network_rule_set = {
      default_action = "Allow"
      ip_rules = [
        {
          action   = "Allow"
          ip_range = "invalid-ip-format"
        }
      ]
    }
  }

  module {
    source = "../../../../modules/azure/container_registry"
  }
}

# Test key vault key ID validation
run "invalid_key_vault_key_id" {
  command = plan
  variables {
    sku                = "Premium"
    encryption_enabled = true
    key_vault_key_id   = "invalid-key-vault-key-id"
  }

  module {
    source = "../../../../modules/azure/container_registry"
  }
}

# Test encryption identity ID validation
run "invalid_encryption_identity_id" {
  command = plan
  variables {
    sku                    = "Premium"
    encryption_enabled     = true
    encryption_identity_id = "invalid-encryption-identity-id"
  }

  module {
    source = "../../../../modules/azure/container_registry"
  }
}

# Test retention policy days validation
run "invalid_retention_policy_days" {
  command = plan
  variables {
    sku                   = "Premium"
    retention_policy_days = 500
  }

  module {
    source = "../../../../modules/azure/container_registry"
  }
}

# Test tags validation - key length
run "invalid_tags_key_length" {
  command = plan
  variables {
    tags = {
      "" = "empty-key-not-allowed"
    }
  }

  module {
    source = "../../../../modules/azure/container_registry"
  }
}

# Test tags validation - value length
run "invalid_tags_value_length" {
  command = plan
  variables {
    tags = {
      "test" = join("", [for i in range(300) : "a"])
    }
  }

  module {
    source = "../../../../modules/azure/container_registry"
  }
} 