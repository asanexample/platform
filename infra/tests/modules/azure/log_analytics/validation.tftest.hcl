/**
 * # Log Analytics Module - Validation Test
 * 
 * This test verifies the validation rules for the Log Analytics module's variables.
 */

variables {
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id       = "c945e155-be68-4477-b8d7-01939adbfe55"
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}

# Test validation for retention period - must be between 30 and 730 days
run "validate_retention_period" {
  command = plan

  module {
    source = "../../../../modules/azure/log_analytics"
  }

  variables {
    resource_group_name = "rg-test-log-analytics"
    location            = "eastus"
    name                = "log-test-validation"
    retention_in_days   = 20 # Invalid: Less than minimum 30 days
  }

  expect_failures = [
    var.retention_in_days
  ]
}

# Test validation for SKU - must be one of the allowed values
run "validate_sku" {
  command = plan

  module {
    source = "../../../../modules/azure/log_analytics"
  }

  variables {
    resource_group_name = "rg-test-log-analytics"
    location            = "eastus"
    name                = "log-test-validation"
    sku                 = "InvalidSKU" # Invalid: Not in allowed list
  }

  expect_failures = [
    var.sku
  ]
}

# Test validation for daily quota - must be non-negative
run "validate_daily_quota" {
  command = plan

  module {
    source = "../../../../modules/azure/log_analytics"
  }

  variables {
    resource_group_name = "rg-test-log-analytics"
    location            = "eastus"
    name                = "log-test-validation"
    daily_quota_gb      = -5 # Invalid: Negative value
  }

  expect_failures = [
    var.daily_quota_gb
  ]
}

# Test validation for role assignments - role definition name must be valid
run "validate_role_assignments" {
  command = plan

  module {
    source = "../../../../modules/azure/log_analytics"
  }

  variables {
    resource_group_name = "rg-test-log-analytics"
    location            = "eastus"
    name                = "log-test-validation"
    role_assignments = [
      {
        role_definition_name = "" # Invalid: Empty string
        principal_id         = "00000000-0000-0000-0000-000000000000"
      }
    ]
  }

  # Now testing variable validation for non-empty role_definition_name
  expect_failures = [
    var.role_assignments
  ]
} 