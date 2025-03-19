# AKS Identity Update Module (DEPRECATED)

> **IMPORTANT: This module is deprecated.**  
> The two-phase deployment approach is no longer necessary. The functionality has been integrated into the `identities` module with an improved approach that handles the dependencies internally. Please use the standard `hosting` module or `aks_cluster_composite` module for AKS deployments.

This module previously handled the second phase of identity configuration for AKS clusters. It created federated credentials and role assignments that depend on the cluster already being provisioned.

## Historical: Two-Phase Deployment Approach

This module was created to work around Terraform's limitation with count arguments that depend on resource attributes unknown until apply time. The deployment had to be split into two phases:

1. **Phase 1 (Infrastructure)**: Deploy the basic AKS infrastructure without the identity update module
2. **Phase 2 (Identity)**: Deploy the identity update module after the AKS cluster is created

## Current Approach

The new approach implemented in the `identities` module and `aks_cluster_composite` module uses a combination of:

1. Creating identities without federated credentials as a first step
2. Creating the AKS cluster with those identities
3. Setting up federated credentials and role assignments using the OIDC issuer URL from the created cluster

This approach eliminates the need for manual multi-phase deployments and simplifies the user experience.

## Migration

To migrate from the two-phase approach:

1. Update your Terragrunt configurations to use the latest hosting module
2. Remove any references to `deployment_mode` variables
3. Use the standard deployment process with no phasing required

## Module Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| resource_group_name | The name of the resource group | `string` | n/a | yes |
| location | The Azure region where resources will be created | `string` | n/a | yes |
| cluster_name | The name of the AKS cluster | `string` | n/a | yes |
| create_workload_identities | Whether to create workload identities | `bool` | `true` | no |
| workload_identity_enabled | Whether workload identity is enabled on the AKS cluster | `bool` | `true` | no |
| oidc_issuer_enabled | Whether OIDC issuer is enabled on the AKS cluster | `bool` | `true` | no |
| oidc_issuer_url | The OIDC issuer URL of the AKS cluster | `string` | `null` | no |
| node_resource_group_id | The ID of the node resource group | `string` | `null` | no |
| tags | Tags to apply to resources | `map(string)` | `{}` | no |

## Module Outputs

| Name | Description |
|------|-------------|
| karpenter_identity_id | The ID of the Karpenter identity |
| karpenter_identity_principal_id | The principal ID of the Karpenter identity |
| karpenter_identity_client_id | The client ID of the Karpenter identity | 