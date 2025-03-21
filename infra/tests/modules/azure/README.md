# Azure Module Tests

This directory contains comprehensive tests for our Azure infrastructure modules. The tests are written using Terraform's built-in testing framework and follow a consistent pattern across all modules.

## Test Structure

Each module follows a consistent test structure:

1. **Basic Test (`basic.tftest.hcl`)**: Verifies core functionality with minimal configuration.
2. **Advanced Test (`advanced.tftest.hcl`)**: Tests optional features and complex configurations.
3. **Validation Test (`validation.tftest.hcl`)**: Checks edge cases and variable constraints.

## Running Tests

You can run tests for all modules or for a specific module:

```bash
# Run all tests
cd infra && make test

# Run tests for a specific module
cd infra && terraform test -test-directory=tests/modules/azure/resource_group
```

## Testing Approach

Our tests follow these key principles:

1. **Actual Provider Configuration**: Tests use actual Azure credentials via environment variables or the Azure CLI for authentication.
2. **Plan-Only Testing**: Tests use `command = plan` to validate resource configurations without creating actual resources.
3. **Assertion-Based Validation**: Each test includes assertions to verify expected resource properties.
4. **Progressive Complexity**: Tests follow a pattern of increasing complexity from basic to advanced scenarios.
5. **Isolated Test Environments**: Tests are designed to be isolated from your actual Azure resources.

## Provider Configuration

All tests use a provider configuration that references your actual Azure credentials:

```hcl
provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id = "c945e155-be68-4477-b8d7-01939adbfe55"
}
```

A helper script at `infra/tests/setup_azure_creds.sh` will automatically set up your current Azure credentials for the tests.

## Tested Modules

The test suite covers the following Azure modules:

| Category | Modules | Status |
|----------|---------|--------|
| Core Infrastructure | Resource Group, Storage Account, Key Vault | ✅ Completed |
| Monitoring | Log Analytics, Monitor Workspace | ✅ Completed |
| Identity | Client Config | ✅ Completed |
| Networking | Private DNS | ✅ Completed |
| Kubernetes | AKS Core | ✅ Completed |
| Pending | AKS Node Pools, AKS Identity, Networking, Storage Container, Storage Roles, Identities, Naming, Terraform State, Managed Grafana, Kubernetes | 🔄 In Progress |

## Test Assertions

Each test includes assertions that verify:

1. **Resource Names**: Correct resource naming based on input parameters or naming conventions.
2. **Core Properties**: Essential resource configuration like location, SKU, etc.
3. **Optional Features**: Advanced configurations that should be applied correctly.
4. **Relationships**: Proper connections between resources.

## Adding New Tests

When adding tests for a new module, follow these steps:

1. Create a new directory under `tests/modules/azure/<module-name>`.
2. Add at minimum:
   - `basic.tftest.hcl` - Minimal configuration test
   - `advanced.tftest.hcl` - Complex configuration test (for modules with advanced features)
   - `validation.tftest.hcl` - Validation test (for modules with complex validation rules)
3. Use the provider configuration pattern shown in existing tests.
4. Include appropriate assertions matching the module's outputs.
5. Use the established patterns from existing tests as a reference.

## Authentication

Tests require Azure authentication. Since we're using the `plan` command, no actual resources are created, but valid credentials are still required. Tests are configured to use the pre-configured credentials, but you can log in before running tests:

```bash
az login
az account set --subscription <subscription-id>
```

Or you can simply run:

```bash
make test
```

Which will automatically set up your credentials.

## Test Maintenance

As modules evolve, tests should be updated to reflect changes:

1. When a new parameter is added, update relevant tests.
2. If a default value changes, verify test assertions still pass.
3. When a feature is deprecated, add tests for the new recommended pattern.

## Test Naming and Structure

For consistency, follow these conventions:

1. **File Names**:
   - `basic.tftest.hcl` - Basic functionality
   - `advanced.tftest.hcl` - Advanced features
   - `validation.tftest.hcl` - Input validation

2. **Run Names**:
   - Use descriptive names like `basic_resource_group`, `advanced_storage_account`
   - For validation tests, use names that describe what's being validated

3. **Test Organization**:
   - Start with the provider block
   - Define variables
   - Specify the module source
   - Add assertions

4. **Comments**:
   - Include a module description at the top of each test file
   - Group variables with comments that explain their purpose
   - Add comments for complex assertions 