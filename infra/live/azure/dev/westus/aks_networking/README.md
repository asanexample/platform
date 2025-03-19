# ⚠️ DEPRECATED - AKS Networking Module

## Module Deprecation Notice

This module has been **deprecated** and its functionality consolidated into the main `networking` module. The consolidation was done to:

1. **Eliminate Resource Conflicts**: Both modules were managing the same subnet NSG association resource, causing apply failures.
2. **Simplify Architecture**: Keeping networking concerns in a single module improves clarity and maintainability.
3. **Reduce Redundancy**: The separate module created duplicate resources for managing the same subnets.

## Migration Path

If you were previously using this module, use the main networking module with AKS-specific parameters instead:

```hcl
# In networking/terragrunt.hcl
inputs = {
  # Regular networking parameters...
  vnet_name = dependency.naming.outputs.virtual_network
  address_space = ["10.9.0.0/16"]
  
  subnets = {
    "az1-node-subnet" = {
      address_prefixes = ["10.9.0.0/20"]
    }
    # Other subnets...
  }

  # AKS Networking Configuration
  enable_aks_networking = true
  aks_subnet_name = "az1-node-subnet"
  aks_cluster_name = dependency.naming.outputs.aks_cluster
  aks_private_cluster_enabled = true
  aks_node_resource_group = "${dependency.resource_group.outputs.name}-nodes"
}
```

## Technical Details of the Consolidation

The main `networking` module now provides the following AKS-specific features:

1. **AKS-Specific NSG Rules**:
   - AllowAzureLoadBalancer rule (priority 100)
   - DenyAllInbound rule (priority 4096)

2. **Private DNS Zone Support**:
   - Creates privatelink.{region}.azmk8s.io zone for private clusters
   - Links the zone to your VNet

3. **Outputs**:
   - `aks_subnet_id`: ID of the AKS node subnet
   - `aks_private_dns_zone_id`: ID of the AKS private DNS zone
   - `vnet_subnet_ids`: List of all subnet IDs

## Status of This Module

This module is kept for reference but has the `skip = true` parameter set in its Terragrunt configuration, meaning it will be skipped during apply operations. 