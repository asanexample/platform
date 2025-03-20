# Troubleshooting Guide

## Overview

This guide provides solutions to common issues encountered when working with the VIP Platform. It includes troubleshooting steps, diagnostic procedures, and resolution strategies for various components of the infrastructure.

*This document is under development. The full content will be available soon.*

## Common Issues

### Deployment Failures

*Detailed troubleshooting steps for deployment failures will be provided in a future update.*

#### Terraform State Lock Issues

**Symptoms**: Terraform operations fail with a message about the state being locked.

**Cause**: A previous Terraform operation did not release the state lock, possibly due to an interrupted operation.

**Resolution**:
1. Check if any Terraform processes are still running
2. If no processes are running, use `terragrunt force-unlock <LOCK_ID>` to release the lock
3. For persistent issues, check the state storage for lock files

#### Module Version Conflicts

**Symptoms**: Terraform fails with errors about incompatible provider versions.

**Cause**: Mismatched version constraints between modules or provider configurations.

**Resolution**:
1. Check version constraints in all modules
2. Ensure consistent provider versions across all configurations
3. Use `terraform init -upgrade` to update providers

### Network Connectivity Issues

*Detailed troubleshooting steps for network connectivity issues will be provided in a future update.*

### Kubernetes Cluster Issues

#### AKS Cluster Recreation During Apply

**Symptoms**: Running `terragrunt apply` or `terraform apply` indicates that the AKS cluster will be destroyed and recreated, even for seemingly minor changes.

**Cause**: Changes to immutable AKS properties that require recreation rather than in-place updates. Common immutable properties include:

- Location
- Resource group name
- DNS prefix
- Network plugin type
- Pod CIDR and Service CIDR
- Virtual network/subnet IDs
- Availability zones configuration
- Node resource group name

**Resolution**:
1. **Identify the Trigger**: In the plan output, look for attributes marked with `# forces replacement`
2. **Evaluate Necessity**: Determine if the change is truly needed; many configuration changes can be made through separate resources without touching immutable properties
3. **Changing Network Settings**:
   - If you need to change the Pod CIDR or network configuration, be aware that it will require cluster recreation
   - For network plugin changes (e.g., from kubenet to Azure CNI or adding Cilium), always create a new cluster rather than modifying an existing one
4. **Managing Properties**:
   - For properties like `pod_cidr` that are typically managed implicitly by Azure, avoid explicitly setting them in Terraform unless necessary
   - If a property like `pod_cidr` was added to configuration and causing recreation, remove it from the configuration to revert to Azure-managed defaults
5. **State Manipulation** (Advanced):
   - As a last resort, use `terraform state rm` to remove the AKS resource from state, then `terraform import` to bring it back without the problematic attribute
   - This should be done with caution and proper backups of the state file

**Prevention**:
1. Fully design AKS clusters before creation, considering all network and identity requirements
2. Use separate modules for aspects that might change (e.g., node pools, monitoring configurations)
3. Document immutable properties in module READMEs to highlight their significance
4. Always run `terraform plan` or `terragrunt plan` before applying changes to identify potential recreations

### Identity and Access Issues

*Detailed troubleshooting steps for identity and access issues will be provided in a future update.*

## Diagnostic Procedures

*Documentation on diagnostic procedures will be provided in a future update.*

## Logs and Monitoring

*Documentation on logs and monitoring will be provided in a future update.*

## Support Process

*Documentation on the support process will be provided in a future update.*

## Prevention Strategies

*Documentation on prevention strategies will be provided in a future update.* 