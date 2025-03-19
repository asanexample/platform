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