# Azure AKS Core Module - East US (Dev)

## Overview
This module provisions and configures the core Azure Kubernetes Service (AKS) cluster in the East US region for the development environment. It sets up a production-ready Kubernetes platform with appropriate security and networking configurations.

## Configuration Details

### Purpose
Creates a production-ready AKS cluster that:
- Provides a secure platform for container workloads
- Follows Azure and Kubernetes best practices
- Implements private networking and enhanced security
- Enables proper monitoring and management

### Dependencies
- **naming**: Uses standardized resource names
- **resource_group**: Deploys resources in the specified resource group
- **networking**: Uses network configuration for cluster networking
- **aks_identity**: Uses managed identity for the AKS cluster
- **log_analytics**: Uses Log Analytics workspace for diagnostics and monitoring

### Key Configuration Settings
- **Cluster Configuration**:
  - Kubernetes Version: 1.27.7 (Stable channel)
  - Private Cluster: Enabled
  - Network Plugin: Azure CNI
  - Network Policy: Azure (configured for eventual Cilium deployment)
  - Outbound Type: User-defined routing
- **System Node Pool**:
  - VM Size: Standard_D4s_v3
  - Node Count: 3-5 (Auto-scaling enabled)
  - Zone Redundancy: Enabled across 3 availability zones
  - OS Disk Type: Ephemeral
  - OS Disk Size: 128 GB
  - Max Pods per Node: 30
- **Security Features**:
  - Workload Identity: Enabled
  - OIDC Issuer: Enabled
  - RBAC: Enabled with Azure AD integration
  - Local accounts: Disabled
  - Microsoft Defender for Containers: Enabled
- **Monitoring and Diagnostics**:
  - Azure Monitor: Enabled
  - Log Analytics Integration: Enabled with dedicated workspace
  - Comprehensive Diagnostic Settings: Enabled for all log categories
  - Kubernetes Control Plane Logs: Collected and analyzed
  - Metrics Collection: All metrics captured for performance analysis

## Implementation Details
The AKS Core module uses the [Azure AKS Module](/infra/modules/azure/aks) to create a standardized Kubernetes environment with:

- System node pool configurations optimized for Kubernetes system components
- Identity configuration using managed identities for enhanced security
- Network integration with the VNet created by the networking module
- Support for workload identity for pod-based authentication
- Maintenance window configured for off-peak hours
- Comprehensive diagnostics for monitoring cluster health and performance

## Multi-AZ Design
The cluster is designed with a multi-availability zone architecture:
- System nodes distributed across 3 availability zones
- Dedicated subnet for each availability zone to increase fault tolerance
- Load balancer configured for zone-redundant operation

## Monitoring and Diagnostics
The cluster is configured with comprehensive monitoring and diagnostics:

### Diagnostic Settings Configuration
Monitoring and diagnostics are configured through the `terragrunt.hcl` file using the Log Analytics workspace from the log_analytics module dependency. This approach enables:

- Centralized diagnostics configuration through Terragrunt
- Integration with the Log Analytics workspace 
- Consolidated monitoring of AKS and other Azure resources

The diagnostic settings are applied directly in the `terragrunt.hcl` with this configuration:

```hcl
# AKS Diagnostic Settings
diagnostic_settings = [
  {
    name                       = "${dependency.naming.outputs.aks_cluster}-diag"
    log_analytics_workspace_id = dependency.log_analytics.outputs.id
    
    # Enable all log categories for comprehensive monitoring
    enabled_log_categories = [
      "kube-apiserver",
      "kube-audit",
      "kube-audit-admin",
      "kube-controller-manager",
      "kube-scheduler",
      "cluster-autoscaler",
      "cloud-controller-manager",
      "guard",
      "csi-azuredisk-controller",
      "csi-azurefile-controller",
      "csi-snapshot-controller"
    ]
    
    # Enable all metrics
    metric_categories = [
      "AllMetrics"
    ]
    
    # Log retention days
    log_retention_days = 30
  }
]
```

This configuration ensures that all critical Kubernetes control plane logs are captured and stored in the Log Analytics workspace for analysis.

### Diagnostic Categories
- **Kubernetes API Server Logs**: Track all API requests and responses
- **Kubernetes Audit Logs**: Capture all changes to cluster resources
- **Control Plane Component Logs**: Monitor scheduler, controller manager, etc.
- **Cluster Autoscaler Logs**: Track scaling decisions and events
- **CSI Controller Logs**: Monitor storage operations and issues

### Monitoring Capabilities
- **Real-time Metrics**: CPU, memory, network, and disk usage
- **Alert Configuration**: Automatic alerts for critical issues
- **Dashboard Integration**: Pre-configured visualization in Azure Portal
- **Log Queries**: Ability to run custom queries against collected logs

## Post-Deployment Configuration
After deployment, additional components are installed through Kubernetes manifests and Helm charts:
- Cilium CNI (replaces Azure CNI for networking)
- Cert-Manager for certificate management
- External-DNS for DNS automation
- Ingress controllers for traffic management

## Usage Example

To apply this module:
```bash
cd aks_core
terragrunt apply
```

To view cluster credentials after deployment:
```bash
cd aks_core
terragrunt output kube_config_raw > ~/.kube/config
```

To query diagnostic logs after deployment:
```bash
# View API server errors in the last hour
az monitor log-analytics query \
  --workspace $(terragrunt output log_analytics_workspace_id) \
  --query "AzureDiagnostics | where Category == 'kube-apiserver' and TimeGenerated > ago(1h) and Level == 'Error' | project TimeGenerated, Log" \
  --analytics-query
```

## Dependencies on this Module
The following modules depend on outputs from this module:
- aks_node_pools 

## Maintenance and Updates
The AKS cluster is configured with automatic upgrades through the "stable" channel. This ensures the cluster receives security patches and minor version updates automatically, while major version upgrades are handled manually.

Maintenance windows are configured for Sundays between 00:00-03:00 UTC to minimize disruption to workloads. 