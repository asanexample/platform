# Documentation and Configuration Updates

This document tracks significant changes and fixes made to the platform infrastructure.

## Recent Updates

### 1. Key Vault Naming Strategy

**Issue**: Azure Key Vault requires globally unique names. The initial implementation used a timestamp-based naming approach (`vipdeveuskv${local.timestamp_suffix}`), which caused the Key Vault to be recreated on each apply.

**Fix**: Implemented a static unique suffix approach:

```hcl
locals {
  unique_suffix = "01"
}

inputs = {
  name = "vipdevwuskv${local.unique_suffix}"
}
```

**Files Updated**:
- `infra/live/azure/dev/westus/keyvault/terragrunt.hcl` - Added static suffix
- `infra/live/azure/dev/westus/keyvault/README.md` - Created documentation
- `infra/modules/azure/key_vault/README.md` - Updated documentation

### 2. AKS Identity Naming Attribute Fix

**Issue**: Terragrunt configurations referenced non-existent attributes from the naming module (`user_assigned_identity` and `user_managed_identity` instead of `aks_identity`).

**Fix**: Updated references to use the correct attribute name:

```hcl
dependency "naming" {
  config_path = "../naming"
  mock_outputs = {
    aks_identity = "mock-identity"  # Correct attribute name
  }
}

inputs = {
  aks_identity_name = dependency.naming.outputs.aks_identity  # Correct reference
}
```

**Files Updated**:
- `infra/live/azure/dev/westus/aks_identity/README.md` - Created documentation
- Verified `infra/live/azure/dev/westus/aks_identity/terragrunt.hcl` - Already using correct attribute
- `README.md` - Added troubleshooting section

### 3. State Lock Resolution

**Issue**: Terraform state locks preventing operations when another process holds the lock.

**Solution**:
- Added documentation on checking for running operations
- Added documentation on how to unlock the state:
  ```bash
  terragrunt force-unlock <LOCK_ID>
  ```
- Added instructions for manual lock file removal (when needed):
  ```bash
  rm -f .terraform.tfstate.lock.info
  ```

**Files Updated**:
- `README.md` - Added troubleshooting section

### 4. Terragrunt Cache Clearing

**Issue**: Corrupted or outdated Terragrunt cache causing unexpected errors.

**Solution**: Added documentation for clearing the Terragrunt cache:

```bash
# Find and remove Terragrunt cache directories
find infra/live/azure/dev/westus -type d -name ".terragrunt-cache" -exec rm -rf {} \; 2>/dev/null || true

# Remove Terraform state files
find infra/live/azure/dev/westus -name ".terraform*" -exec rm -rf {} \;
find infra/live/azure/dev/westus -name "terraform.tfstate*" -exec rm -rf {} \;
```

**Files Updated**:
- `README.md` - Added troubleshooting section

### 5. Networking Module Consolidation

**Issue**: Duplicate management of network resources causing conflicts. The `networking` and `aks_networking` modules were both trying to manage the same subnet NSG associations, causing apply failures.

**Solution**: Consolidated all networking features into a single module with optional AKS-specific capabilities:

```hcl
# In networking/terragrunt.hcl
inputs = {
  # Regular networking parameters...
  
  # AKS Networking Configuration
  enable_aks_networking = true
  aks_subnet_name = "az1-node-subnet"
  aks_cluster_name = dependency.naming.outputs.aks_cluster
  aks_private_cluster_enabled = true
  aks_node_resource_group = "${dependency.resource_group.outputs.name}-nodes"
}
```

**Files Updated**:
- `infra/modules/azure/networking/variables.tf` - Added AKS-specific parameters
- `infra/modules/azure/networking/main.tf` - Added AKS networking resources
- `infra/modules/azure/networking/outputs.tf` - Added AKS-specific outputs
- `infra/modules/azure/networking/README.md` - Updated documentation
- `infra/live/azure/dev/westus/networking/terragrunt.hcl` - Added AKS networking parameters
- `infra/live/azure/dev/westus/networking/README.md` - Added documentation for the new capabilities
- `infra/live/azure/dev/westus/aks_networking/terragrunt.hcl` - Marked as deprecated with `skip = true`
- `infra/live/azure/dev/westus/aks_networking/README.md` - Added deprecation notice
- `infra/modules/azure/aks_networking/README.md` - Added deprecation notice
- `infra/live/azure/dev/westus/aks_core/terragrunt.hcl` - Updated to use the consolidated networking module

## Recommendations for Future Development

1. **Naming Convention Validation**:
   - Consider adding a CI/CD validation step to ensure that all Terragrunt configurations use correct attribute names from the naming module.

2. **Resource Naming Strategy**:
   - For globally unique resources, avoid timestamp-based naming that causes recreation.
   - Use environment-specific static suffixes that remain consistent across deployments.

3. **Documentation Standards**:
   - Ensure each Terragrunt configuration has a corresponding README.md file.
   - Include examples, known issues, and dependencies in all module documentation.

4. **State Management**:
   - Consider implementing a central remote state management approach using Azure Storage.
   - Document state lock resolution procedures for team members.

5. **Module Design**:
   - Follow the Single Responsibility Principle by consolidating related functionality in a single module.
   - Design modules to be flexible with optional features rather than creating separate modules for slight variations.
   - Use flags and conditionals to enable/disable specific features within modules. 