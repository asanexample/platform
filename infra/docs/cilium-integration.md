# Cilium CNI Integration with AKS

This document outlines the integration of Cilium CNI with Azure Kubernetes Service (AKS), detailing the configuration, benefits, and implementation process.

## Overview

Cilium is an advanced, eBPF-based networking solution for Kubernetes that provides high-performance networking, security, and observability. In our infrastructure, Cilium is deployed as the sole CNI (Container Network Interface) for AKS clusters, replacing the need for Azure CNI.

## Integration Approach

The integration of Cilium with AKS follows this approach:

1. **Initial Deployment**: 
   - AKS clusters are deployed with no CNI installed (`network_plugin = "none"`)
   - This allows Cilium to be the first and only CNI in the cluster

2. **Cilium Installation**: 
   - Cilium is installed via Helm after the cluster is provisioned
   - Configured for Azure-specific integration with the required IAM permissions

3. **No CNI Replacement**: 
   - Unlike traditional approaches, we don't install Azure CNI first and then replace it
   - Cilium is the only CNI ever installed on the cluster

## Infrastructure Preparation

### AKS Core Configuration

The following configuration is used in the AKS core module to prepare for Cilium:

```hcl
module "aks_core" {
  # ... other configuration ...
  
  # Network configuration - no CNI installed by default
  network_plugin = "none"
  network_policy = null
  
  # Pod CIDR will be managed by Cilium
  pod_cidr = null
  
  # ... other configuration ...
}
```

### Node Pool Configuration

Node pools are configured with higher pod density limits to leverage Cilium's efficient IP allocation:

```hcl
module "aks_node_pools" {
  # ... other configuration ...
  
  # Higher pod density with Cilium
  app_node_pool_max_pods = 110
  
  # ... other configuration ...
}
```

### Tags for Cilium Management

The following Azure resource tags are recommended for clusters using Cilium:

```hcl
tags = {
  "network-plugin" = "cilium"
  "cilium-version" = "1.14.2"
}
```

### Networking Configuration

Network Security Groups (NSGs) must allow the following traffic for Cilium to function properly:

1. Node-to-node traffic on ports:
   - TCP 4240 (health checks)
   - UDP 8472 (VXLAN)
   - TCP/UDP 4244 (Hubble)
   - UDP 51871 (WireGuard, if encryption is enabled)

2. Ensure the AKS identity has permissions to:
   - Read instance information
   - Manage network interfaces
   - Read Azure IMDS

## Benefits

Using Cilium as the sole CNI for AKS provides the following benefits:

1. **Enhanced Network Policies**: Beyond standard Kubernetes network policies, Cilium provides L7 policies based on HTTP/gRPC/DNS.

2. **Advanced Security**: Enhanced security with identity-based policies and transparent encryption.

3. **Improved Performance**: eBPF-based datapath offers better performance compared to the Azure CNI.

4. **Better Observability**: Hubble integration provides detailed network flow visibility.

5. **Higher Pod Density**: More efficient IP address management allows for higher pod density per node.

## Installation Process

After the AKS infrastructure is deployed, install Cilium as follows:

1. **Add the Cilium Helm Repository**:

   ```bash
   helm repo add cilium https://helm.cilium.io/
   helm repo update
   ```

2. **Deploy Cilium Using Helm**:

   ```bash
   helm install cilium cilium/cilium \
     --version 1.14.2 \
     --namespace kube-system \
     --set azure.enabled=true \
     --set azure.resourceGroup=${RESOURCE_GROUP} \
     --set azure.subscriptionID=${SUBSCRIPTION_ID} \
     --set azure.tenantID=${TENANT_ID} \
     --set azure.userAssignedIdentity=${USER_ASSIGNED_IDENTITY_CLIENT_ID} \
     --set ipam.mode=kubernetes \
     --set hubble.enabled=true \
     --set hubble.relay.enabled=true \
     --set hubble.ui.enabled=true
   ```

3. **Verify Installation**:

   ```bash
   # If Cilium CLI is installed
   cilium status --wait
   
   # Using kubectl
   kubectl get pods -n kube-system -l k8s-app=cilium
   ```

4. **Test Connectivity**:

   ```bash
   kubectl create ns cilium-test
   cilium connectivity test --namespace cilium-test
   ```

For more detailed installation instructions, refer to the [Cilium Installation Guide](cilium-installation.md).

## Common Troubleshooting Commands

1. **Check Cilium Agent Status**:

   ```bash
   cilium status
   ```

2. **View Cilium Agent Logs**:

   ```bash
   kubectl logs -n kube-system -l k8s-app=cilium --tail=100
   ```

3. **Verify Network Policies**:

   ```bash
   cilium policy get
   ```

4. **Check eBPF Maps**:

   ```bash
   cilium bpf policy get
   ```

## Limitations and Considerations

1. **Initial Network Gap**: Since AKS is deployed without any CNI, pods won't be able to communicate until Cilium is installed. This process should be automated to minimize the gap.

2. **API Server Connectivity**: Ensure proper configuration for API server access.

3. **Upgrade Process**: When upgrading Cilium, follow the recommended upgrade path from the Cilium documentation.

4. **Version Compatibility**: Validate Cilium version compatibility with the Kubernetes version in AKS.

## References

- [Cilium Documentation](https://docs.cilium.io/)
- [AKS Documentation](https://docs.microsoft.com/en-us/azure/aks/)
- [Cilium Installation Guide](cilium-installation.md) 