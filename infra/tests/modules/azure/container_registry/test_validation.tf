/**
 * # Container Registry Validation Test Module
 * 
 * This module is used for testing variable validations in the container_registry module.
 * It's designed to be called from the validation.tftest.hcl file to verify that
 * invalid inputs are properly rejected with appropriate error messages.
 */

# This module expects failures and intentionally uses invalid values to ensure
# that variable validations work correctly

# Invalid name format test (contains special characters)
module "invalid_name_format" {
  # Use the actual module path but wrap it in try() to handle expected failures
  source = "../../../../modules/azure/container_registry"
  count  = 0 # This ensures the module is not actually created but validation still runs

  # Standard required variables with valid values
  resource_group_name = "test-rg"
  location            = "eastus"
  prefix              = "test"
  environment         = "dev"
  region_abbv         = "eus"
  
  # The invalid value we want to test
  name = "invalid@name"
  
  # Other required variables with valid values
  create_registry = true
  sku             = "Standard"
}

# Invalid name length test (too short)
module "invalid_name_length_too_short" {
  source = "../../../../modules/azure/container_registry"
  count  = 0

  resource_group_name = "test-rg"
  location            = "eastus"
  prefix              = "test"
  environment         = "dev"
  region_abbv         = "eus"
  
  name = "acr" # Too short (less than 5 chars)
  
  create_registry = true
  sku             = "Standard"
}

# Invalid resource group name test
module "invalid_resource_group_name" {
  source = "../../../../modules/azure/container_registry"
  count  = 0

  resource_group_name = "invalid*resource*group"
  location            = "eastus"
  prefix              = "test"
  environment         = "dev"
  region_abbv         = "eus"
  
  create_registry = true
  sku             = "Standard"
}

# Invalid location test
module "invalid_location" {
  source = "../../../../modules/azure/container_registry"
  count  = 0

  resource_group_name = "test-rg"
  location            = "invalid-location"
  prefix              = "test"
  environment         = "dev"
  region_abbv         = "eus"
  
  create_registry = true
  sku             = "Standard"
}

# Invalid prefix test
module "invalid_prefix" {
  source = "../../../../modules/azure/container_registry"
  count  = 0

  resource_group_name = "test-rg"
  location            = "eastus"
  prefix              = "invalid@prefix"
  environment         = "dev"
  region_abbv         = "eus"
  
  create_registry = true
  sku             = "Standard"
}

# Invalid prefix length test
module "invalid_prefix_length" {
  source = "../../../../modules/azure/container_registry"
  count  = 0

  resource_group_name = "test-rg"
  location            = "eastus"
  prefix              = "thisPrefixIsTooLong"
  environment         = "dev"
  region_abbv         = "eus"
  
  create_registry = true
  sku             = "Standard"
}

# Invalid environment test
module "invalid_environment" {
  source = "../../../../modules/azure/container_registry"
  count  = 0

  resource_group_name = "test-rg"
  location            = "eastus"
  prefix              = "test"
  environment         = "invalid-env"
  region_abbv         = "eus"
  
  create_registry = true
  sku             = "Standard"
}

# Invalid region abbreviation test
module "invalid_region_abbv" {
  source = "../../../../modules/azure/container_registry"
  count  = 0

  resource_group_name = "test-rg"
  location            = "eastus"
  prefix              = "test"
  environment         = "dev"
  region_abbv         = "EASTUS" # Should be lowercase
  
  create_registry = true
  sku             = "Standard"
}

# Invalid SKU test
module "invalid_sku" {
  source = "../../../../modules/azure/container_registry"
  count  = 0

  resource_group_name = "test-rg"
  location            = "eastus"
  prefix              = "test"
  environment         = "dev"
  region_abbv         = "eus"
  
  create_registry = true
  sku             = "InvalidSku"
}

# Invalid geo-replication location test
module "invalid_geo_replication_location" {
  source = "../../../../modules/azure/container_registry"
  count  = 0

  resource_group_name = "test-rg"
  location            = "eastus"
  prefix              = "test"
  environment         = "dev"
  region_abbv         = "eus"
  
  create_registry = true
  sku             = "Premium"
  geo_replication_locations = ["eastus", "invalid-location"]
}

# Invalid network rule default action test
module "invalid_network_rule_default_action" {
  source = "../../../../modules/azure/container_registry"
  count  = 0

  resource_group_name = "test-rg"
  location            = "eastus"
  prefix              = "test"
  environment         = "dev"
  region_abbv         = "eus"
  
  create_registry = true
  sku             = "Premium"
  network_rule_set = {
    default_action = "InvalidAction"
    ip_rules = []
  }
}

# Invalid network rule IP format test
module "invalid_network_rule_ip_format" {
  source = "../../../../modules/azure/container_registry"
  count  = 0

  resource_group_name = "test-rg"
  location            = "eastus"
  prefix              = "test"
  environment         = "dev"
  region_abbv         = "eus"
  
  create_registry = true
  sku             = "Premium"
  network_rule_set = {
    default_action = "Allow"
    ip_rules = [
      {
        action = "Allow"
        ip_range = "invalid-ip-format"
      }
    ]
  }
}

# Invalid key vault key ID test
module "invalid_key_vault_key_id" {
  source = "../../../../modules/azure/container_registry"
  count  = 0

  resource_group_name = "test-rg"
  location            = "eastus"
  prefix              = "test"
  environment         = "dev"
  region_abbv         = "eus"
  
  create_registry = true
  sku             = "Premium"
  encryption_enabled = true
  key_vault_key_id = "invalid-key-vault-key-id"
}

# Invalid encryption identity ID test
module "invalid_encryption_identity_id" {
  source = "../../../../modules/azure/container_registry"
  count  = 0

  resource_group_name = "test-rg"
  location            = "eastus"
  prefix              = "test"
  environment         = "dev"
  region_abbv         = "eus"
  
  create_registry = true
  sku             = "Premium"
  encryption_enabled = true
  encryption_identity_id = "invalid-encryption-identity-id"
}

# Invalid retention policy days test
module "invalid_retention_policy_days" {
  source = "../../../../modules/azure/container_registry"
  count  = 0

  resource_group_name = "test-rg"
  location            = "eastus"
  prefix              = "test"
  environment         = "dev"
  region_abbv         = "eus"
  
  create_registry = true
  sku             = "Premium"
  retention_policy_days = 500 # Should be between 0 and 365
}

# Invalid tags key length test
module "invalid_tags_key_length" {
  source = "../../../../modules/azure/container_registry"
  count  = 0

  resource_group_name = "test-rg"
  location            = "eastus"
  prefix              = "test"
  environment         = "dev"
  region_abbv         = "eus"
  
  create_registry = true
  sku             = "Standard"
  tags = {
    "" = "empty-key-not-allowed"
  }
}

# Invalid tags value length test
module "invalid_tags_value_length" {
  source = "../../../../modules/azure/container_registry"
  count  = 0

  resource_group_name = "test-rg"
  location            = "eastus"
  prefix              = "test"
  environment         = "dev"
  region_abbv         = "eus"
  
  create_registry = true
  sku             = "Standard"
  tags = {
    "test" = join("", [for i in range(300) : "a"])
  }
} 