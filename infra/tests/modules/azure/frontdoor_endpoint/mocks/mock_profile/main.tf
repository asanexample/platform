/**
 * Mock Front Door profile for endpoint tests
 */

# This is a test-only mock that doesn't need to actually create resources
# It just provides the output structure needed for the test
output "id" {
  value = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/test-rg/providers/Microsoft.Cdn/profiles/mock-fd-profile"
}

output "name" {
  value = "mock-fd-profile"
} 