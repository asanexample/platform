# Define provider configuration for the test runs
provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id       = "c945e155-be68-4477-b8d7-01939adbfe55"
  # Skip resource provider registration for tests
  resource_provider_registrations = "none"
}

/**
 * # Front Door Endpoint Module - Advanced Test
 * 
 * This test verifies advanced functionality of the Front Door Endpoint module
 * with load balancing and health probe configurations.
 */

# Test Front Door Endpoint with load balancing settings
run "load_balancing_test" {
  command = plan

  variables {
    enabled                  = true
    endpoint_name            = "test-endpoint"
    origin_group_name        = "test-origin-group"
    profile_name             = "mock-fd-profile"
    profile_resource_group_name = "test-rg"
    profile_id               = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/test-rg/providers/Microsoft.Cdn/profiles/mock-fd-profile"
    
    # Load balancing settings
    load_balancing_enabled   = true
    load_balancing_settings  = {
      additional_latency_in_milliseconds = 50
      sample_size                        = 4
      successful_samples_required        = 3
    }
    
    tags = {
      environment = "test"
    }
  }

  module {
    source = "../../../../modules/azure/frontdoor_endpoint"
  }

  # Verify load balancing settings
  assert {
    condition     = azurerm_cdn_frontdoor_origin_group.this[0].load_balancing[0].additional_latency_in_milliseconds == 50
    error_message = "Origin group should have the specified additional latency"
  }
  
  assert {
    condition     = azurerm_cdn_frontdoor_origin_group.this[0].load_balancing[0].sample_size == 4
    error_message = "Origin group should have the specified sample size"
  }
  
  assert {
    condition     = azurerm_cdn_frontdoor_origin_group.this[0].load_balancing[0].successful_samples_required == 3
    error_message = "Origin group should have the specified successful samples required"
  }
}

# Test Front Door Endpoint with health probe settings
run "health_probe_test" {
  command = plan

  variables {
    enabled                  = true
    endpoint_name            = "test-endpoint"
    origin_group_name        = "test-origin-group"
    profile_name             = "mock-fd-profile"
    profile_resource_group_name = "test-rg"
    profile_id               = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/test-rg/providers/Microsoft.Cdn/profiles/mock-fd-profile"
    
    # Load balancing settings (required)
    load_balancing_enabled   = true
    load_balancing_settings = {
      additional_latency_in_milliseconds = 50
      sample_size                        = 4
      successful_samples_required        = 3
    }
    
    # Health probe settings
    health_probe_enabled     = true
    health_probe_settings    = {
      protocol            = "Https"
      interval_in_seconds = 60
      path                = "/health"
      request_type        = "GET"
    }
    
    tags = {
      environment = "test"
    }
  }

  module {
    source = "../../../../modules/azure/frontdoor_endpoint"
  }

  # Verify health probe settings
  assert {
    condition     = azurerm_cdn_frontdoor_origin_group.this[0].health_probe[0].protocol == "Https"
    error_message = "Origin group should have the specified health probe protocol"
  }
  
  assert {
    condition     = azurerm_cdn_frontdoor_origin_group.this[0].health_probe[0].interval_in_seconds == 60
    error_message = "Origin group should have the specified health probe interval"
  }
  
  assert {
    condition     = azurerm_cdn_frontdoor_origin_group.this[0].health_probe[0].path == "/health"
    error_message = "Origin group should have the specified health probe path"
  }
  
  assert {
    condition     = azurerm_cdn_frontdoor_origin_group.this[0].health_probe[0].request_type == "GET"
    error_message = "Origin group should have the specified health probe request type"
  }
}

# Test Front Door Endpoint with both load balancing and health probe settings
run "combined_settings_test" {
  command = plan

  variables {
    enabled                  = true
    endpoint_name            = "test-endpoint"
    origin_group_name        = "test-origin-group"
    profile_name             = "mock-fd-profile"
    profile_resource_group_name = "test-rg"
    profile_id               = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/test-rg/providers/Microsoft.Cdn/profiles/mock-fd-profile"
    
    # Load balancing settings
    load_balancing_enabled   = true
    load_balancing_settings  = {
      additional_latency_in_milliseconds = 50
      sample_size                        = 4
      successful_samples_required        = 3
    }
    
    # Health probe settings
    health_probe_enabled     = true
    health_probe_settings    = {
      protocol            = "Https"
      interval_in_seconds = 60
      path                = "/health"
      request_type        = "GET"
    }
    
    tags = {
      environment = "test"
    }
  }

  module {
    source = "../../../../modules/azure/frontdoor_endpoint"
  }

  # Verify both settings are applied
  assert {
    condition     = can(azurerm_cdn_frontdoor_origin_group.this[0].load_balancing[0]) && can(azurerm_cdn_frontdoor_origin_group.this[0].health_probe[0])
    error_message = "Origin group should have both load balancing and health probe settings"
  }
} 