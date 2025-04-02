/**
 * Mock resources for Front Door Private Link tests
 */

# This is a test-only mock that doesn't need to actually create resources
# It just provides the output structure needed for the test

# Mock origin group
output "origin_group_id" {
  value = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/test-rg/providers/Microsoft.Cdn/profiles/mock-fd-profile/originGroups/mock-origin-group"
}

output "origin_group_name" {
  value = "mock-origin-group"
}

# Mock endpoint
output "endpoint_id" {
  value = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/test-rg/providers/Microsoft.Cdn/profiles/mock-fd-profile/endpoints/mock-endpoint"
}

output "endpoint_name" {
  value = "mock-endpoint"
}

# Mock storage account
output "storage_id" {
  value = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/test-rg/providers/Microsoft.Storage/storageAccounts/mockstorageaccount"
}

output "storage_primary_web_host" {
  value = "mockstorageaccount.z13.web.core.windows.net"
}

output "storage_primary_blob_host" {
  value = "mockstorageaccount.blob.core.windows.net"
}

output "storage_location" {
  value = "eastus"
} 