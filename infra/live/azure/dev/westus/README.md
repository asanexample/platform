# Terragrunt Azure Infrastructure - West US Region

This directory contains Terragrunt configurations for deploying Azure infrastructure in the West US region.

## Structure

Instead of using a monolithic "hosting" module, this configuration uses Terragrunt to orchestrate individual modules:

- **naming**: Centralizes the naming standards for all resources
- **networking**: Manages VNet, subnets, and network security
- **storage**: Provisions storage accounts with proper security settings
- **keyvault**: Sets up Azure Key Vault with network restrictions
- **aks**: Deploys AKS clusters and node pools

## Dependencies

The modules have the following dependencies:

```
naming
  ↑
  |
networking
  ↑
  |--------------|--------------|
  |              |              |
storage       keyvault         aks
```

## Applying Changes

To apply changes, navigate to the directory of the component you want to deploy and run Terragrunt commands:

```bash
cd naming
terragrunt init
terragrunt plan
terragrunt apply
```

To apply all components in the correct order:

```bash
cd ..
terragrunt run-all plan
terragrunt run-all apply
```

## Benefits of This Approach

1. **Separation of state files**: Each component has its own state, reducing risk
2. **Granular deployments**: Apply changes to specific components without affecting others
3. **Explicit dependencies**: Dependencies between resources are clearly defined
4. **Simplified modules**: Individual modules focus on their specific responsibilities
5. **Easier troubleshooting**: Issues are isolated to specific components 