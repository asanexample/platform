# Security Architecture

## Overview

The VIP Platform implements a comprehensive security architecture that enforces defense-in-depth across all infrastructure components. This document outlines the security principles, design patterns, and controls implemented in the platform.

## Security Principles

The security architecture is guided by the following principles:

1. **Defense in Depth**: Multiple layers of security controls throughout the infrastructure.
2. **Least Privilege**: Access limited to only what's necessary for each component and user.
3. **Secure by Default**: Conservative security settings as the starting point.
4. **Identity-Based Security**: Strong identity controls as the foundation of security.
5. **Encryption Everywhere**: Data encrypted both at rest and in transit.
6. **Continuous Validation**: Regular testing and verification of security controls.

## Security Components

### Identity and Access Management

The platform uses Azure's identity services as the foundation for security, implementing:

#### Role-Based Access Control (RBAC)

We implement RBAC through several modules:

- The `storage_roles` module provides granular RBAC for Azure Storage resources:

  ```hcl
  module "storage_roles" {
    source = "../../modules/azure/storage_roles"
    storage_account_id = module.storage_account.id
    role_assignments = [
      {
        principal_id         = data.azuread_group.developers.id
        role_definition_name = "Storage Blob Data Contributor"
        description          = "Grant write access to development team"
      }
    ]
  }
  ```

- Key Vault access policies use RBAC to control access to secrets and certificates
- AKS clusters implement Kubernetes RBAC integrated with Azure AD

#### Managed Identities

User-assigned managed identities are used extensively:

- The `aks_identity` module creates and configures identities specifically for AKS clusters
- The `identities` module creates general-purpose managed identities with appropriate role assignments
- All modules that require identity use these managed identities rather than service principals with credentials

#### Workload Identity

For AKS clusters, we implement Azure Workload Identity for secure pod-based authentication:

- Enables Kubernetes applications to access Azure resources using pod identity
- Eliminates the need for secrets in pod configurations
- Implemented through the `aks_core` module with federation configuration

#### Multi-Factor Authentication

- Admin access to all environments requires MFA through Azure Entra ID
- CI/CD pipelines use service principals with strict scope limitations

### Network Security

#### Network Segmentation

The platform implements network segmentation through:

- Virtual networks with separate subnets for different workload types
- Network security groups (NSGs) attached to each subnet
- Application security groups for fine-grained control

Example from the `networking` module:

```hcl
resource "azurerm_subnet" "subnet" {
  for_each = var.subnets
  
  name                 = each.key
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [each.value.address_prefix]
  service_endpoints    = try(each.value.service_endpoints, [])
}

resource "azurerm_network_security_group" "nsg" {
  for_each = var.subnets
  
  name                = "${each.key}-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name
  
  dynamic "security_rule" {
    for_each = try(flatten([
      for rule_name in each.value.security_rules : [
        var.security_rules[rule_name]
      ]
    ]), [])
    
    content {
      name                       = security_rule.value.name
      priority                   = security_rule.value.priority
      direction                  = security_rule.value.direction
      access                     = security_rule.value.access
      protocol                   = security_rule.value.protocol
      source_port_range          = try(security_rule.value.source_port_range, "*")
      destination_port_range     = try(security_rule.value.destination_port_range, "*")
      source_address_prefix      = try(security_rule.value.source_address_prefix, "*")
      destination_address_prefix = try(security_rule.value.destination_address_prefix, "*")
    }
  }
}
```

#### Private Endpoints

Azure PaaS services are accessed via private endpoints whenever possible:

- The `private_dns` module creates private DNS zones for Azure services
- Private endpoints are configured for:
  - Azure Key Vault
  - Azure Storage Accounts
  - Azure Container Registry
  - Azure Monitor resources

Example for private DNS zones:

```hcl
module "private_dns" {
  source = "../../modules/azure/private_dns"
  resource_group_name = module.resource_group.name
  zones = [
    "privatelink.azurecr.io", 
    "privatelink.vaultcore.azure.net",
    "privatelink.blob.core.windows.net"
  ]
  vnet_links = {
    "hub-vnet" = {
      vnet_id = module.networking.vnet_id
    }
  }
}
```

#### Network Policies

For AKS clusters, network policies are implemented using:

- Azure CNI networking
- Calico network policies for pod-to-pod communication control
- Ingress/egress rules defined at the pod level

#### Edge Security

Front Door is used as a security edge with:

- WAF policies
- DDoS protection
- TLS termination
- Private Link Service for backend connection

### Data Protection

#### Encryption at Rest

All data storage services implement encryption at rest:

- Azure Storage accounts use Azure-managed keys by default
- Azure Key Vault can be configured with customer-managed keys
- AKS etcd encryption is enabled through the `aks_core` module

#### Encryption in Transit

All communication uses TLS encryption:

- Front Door enforces HTTPS with minimum TLS 1.2
- Service-to-service communication uses TLS
- AKS API Server communication is encrypted

#### Key Management

Azure Key Vault is used for centralized key management:

```hcl
module "key_vault" {
  source = "../../modules/azure/key_vault"
  
  name                = "kv-platform-prod-eus"
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  
  network_acls = {
    default_action = "Deny"
    bypass         = "AzureServices"
    ip_rules       = []
    subnet_ids     = [module.networking.subnet_ids["endpoints"]]
  }
  
  access_policies = [
    {
      object_id     = module.client_config.object_id
      certificate_permissions = ["Get", "List", "Create"]
      key_permissions = ["Get", "List", "Create"]
      secret_permissions = ["Get", "List", "Set"]
    }
  ]
}
```

#### Secrets Management

For secrets management, the platform uses:

- Azure Key Vault for storing credentials and certificates
- Managed identities to avoid storing credentials in code
- Kubernetes CSI Driver integration for AKS pods

### Monitoring and Detection

#### Logging and Monitoring

Comprehensive logging is implemented using:

- `log_analytics` module for centralized log collection
- `monitor_workspace` module for metrics storage
- `prometheus_dcr` module for AKS metrics collection

Example:

```hcl
module "log_analytics" {
  source = "../../modules/azure/log_analytics"
  name                = "log-platform-prod-eus"
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  retention_in_days   = 30
  solutions           = ["ContainerInsights"]
}
```

#### Threat Detection

Security monitoring is implemented through:

- Azure Security Center integration
- Container insights for AKS
- Network flow logs analysis
- Azure Sentinel (optional, can be enabled as needed)

#### Security Dashboards

Visualization of security data is provided by:

- `managed_grafana` module for custom security dashboards
- Integration with Azure Monitor for alerting
- Custom queries for threat detection

```hcl
module "managed_grafana" {
  source = "../../modules/azure/managed_grafana"
  name                = "grf-monitoring-prod-eus"
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  sku                 = "Standard"
  
  azure_monitor_workspace_integrations = [
    {
      workspace_id = module.monitor_workspace.id
    }
  ]
}
```

## Security Controls by Environment

The platform implements different security controls based on environment:

### Development Environment

- Network rules are more permissive to facilitate development
- RBAC allows broader access for developers
- Non-production data only

### Production Environment

- Strict network isolation with NSGs and private endpoints
- Limited RBAC access on a need-to-know basis
- Full monitoring and alerting
- Regular security scanning and reviews

## Implementation in Modules

Security is integrated into each module:

### Networking Security

- NSGs with restrictive default rules
- Service endpoints for Azure services
- Network isolation between workloads

### Storage Security

- Public network access disabled by default
- Private endpoints for secure access
- Role-based access control via the `storage_roles` module

### AKS Security

- Azure AD integration
- Network policies enabled
- Pod managed identities
- Control plane security with private API server

### Key Vault Security

- Network ACLs restricting access
- RBAC-based access policies
- Soft-delete and purge protection enabled

## Compliance Tier Enforcement

Security controls are applied based on the `compliance_tier` declared in each workload's `workload.hcl`. The tier determines the isolation model and mandatory controls:

### Standard (SOC2)

- Shared AKS clusters with **vCluster** isolation (CNCF-certified virtual clusters)
- Spoke VNets peered to a central hub
- RBAC, private endpoints, and audit logging enabled by default

### HIPAA

- **Dedicated AKS cluster** (no shared tenancy)
- Isolated VNet with no hub peering by default
- Customer-managed key (CMK) encryption for all data at rest
- Host encryption enabled on all node pools
- Private cluster (no public API server endpoint)
- 365-day log retention

### PCI

- **Dedicated AKS cluster** with all HIPAA controls, plus:
- CDE-segmented VNet with strict boundary controls
- WAF enforced on all ingress paths
- IDS/IPS enabled
- Deny-all default network policy (explicit allow required)

## vCluster Isolation Model

Standard-tier workloads share physical clusters. Tenant isolation is provided by **vCluster**, which gives each team a virtual Kubernetes cluster with its own API server, control plane, and resource namespace. vClusters are CNCF-certified and provide:

- API server isolation (separate authentication and authorization)
- Resource quotas and limit ranges per virtual cluster
- Network policy isolation between virtual clusters
- Independent CRD management

HIPAA and PCI workloads bypass vCluster entirely and run on dedicated physical clusters.

## Kyverno Policy Guardrails

[Kyverno](https://kyverno.io/) is deployed as a policy engine on all clusters to enforce security guardrails at admission time:

- **Image provenance**: Only images from approved registries (ACR) are admitted
- **Pod security**: Enforce restricted pod security standards (no privileged containers, no host networking)
- **Label requirements**: Workload and compliance-tier labels required on all namespaces
- **Network policy enforcement**: Every namespace must have a default-deny network policy (mandatory for PCI, recommended for all tiers)
- **Resource limits**: All pods must declare resource requests and limits

Policies are deployed as Kyverno `ClusterPolicy` resources and are version-controlled alongside infrastructure code.

## Future Security Enhancements

While the current implementation provides a solid security foundation, future enhancements will include:

1. Integration with security scanning tools (tfsec, checkov)
2. Comprehensive compliance mapping for SOC2 and ISO 27001
3. Enhanced security testing frameworks
4. Automated security validation in CI/CD pipelines

## Next Steps

Continue to [Compliance Framework](10-compliance-framework.md) to understand how the security architecture addresses compliance requirements.
