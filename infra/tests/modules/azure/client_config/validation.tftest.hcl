/**
 * # Client Config Module - Validation Test
 * 
 * This test verifies the validation aspects of the client config module,
 * focusing on output types and data integrity.
 */

# Provider configuration with Azure credentials
provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id       = "c945e155-be68-4477-b8d7-01939adbfe55"
  resource_provider_registrations = "none"
}

# Test for output content validation
run "output_content_validation" {
  command = plan

  module {
    source = "../../../../modules/azure/client_config"
  }

  # Validate that tenant ID is output as a string
  assert {
    condition     = try(tostring(output.tenant_id), "") != ""
    error_message = "Tenant ID should be a non-empty string"
  }
  
  # Validate that subscription ID is output as a string
  assert {
    condition     = try(tostring(output.subscription_id), "") != ""
    error_message = "Subscription ID should be a non-empty string"
  }
  
  # Validate that client ID is output as a string (may be empty)
  assert {
    condition     = can(tostring(output.client_id))
    error_message = "Client ID should be a string"
  }
  
  # Validate that object ID is output as a string (may be empty)
  assert {
    condition     = can(tostring(output.object_id))
    error_message = "Object ID should be a string"
  }
}

# Test for consistent output across multiple runs
run "consistent_output_verification" {
  command = plan

  module {
    source = "../../../../modules/azure/client_config"
  }

  # The tenant ID should match the provider's tenant ID
  assert {
    condition     = output.tenant_id == "c945e155-be68-4477-b8d7-01939adbfe55"
    error_message = "Tenant ID should match the provider configuration"
  }
  
  # The subscription ID should match the provider's subscription ID
  assert {
    condition     = output.subscription_id == "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
    error_message = "Subscription ID should match the provider configuration"
  }
}

# Test for data relationships
run "data_relationship_validation" {
  command = plan

  module {
    source = "../../../../modules/azure/client_config"
  }

  # Check that client ID and object ID are provided by the same Terraform run
  assert {
    condition     = (output.client_id == "" && output.object_id == "") || (output.client_id != "" && output.object_id != "")
    error_message = "Client ID and Object ID should both be populated or both be empty, not a mix"
  }
} 