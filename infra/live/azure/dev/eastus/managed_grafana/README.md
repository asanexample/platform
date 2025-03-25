# Azure Managed Grafana Module - East US (Dev)

## Overview
This module provisions and configures an Azure Managed Grafana instance in the East US region for the development environment. The Grafana instance provides a sophisticated visualization and monitoring platform for metrics and logs from various data sources.

## Configuration Details

### Purpose
Creates an Azure Managed Grafana instance that:
- Provides powerful visualization capabilities for metrics and logs
- Integrates with Azure services including Azure Monitor
- Supports integration with Microsoft Entra ID (formerly Azure AD) for authentication
- Enables creation of comprehensive dashboards for development monitoring

### Dependencies
- **naming**: Uses standardized resource names
- **resource_group**: Deploys resources in the specified resource group
- **log_analytics**: Integration with Log Analytics workspace for data source

### Key Configuration Settings
- **Grafana Instance Name**: Uses standardized naming convention (`vip-dev-grafana-eus`)
- **Version**: Grafana major version 10
- **Security Features**:
  - API Key Authentication: Enabled
  - Public Network Access: Enabled
  - Zone Redundancy: Enabled for high availability
- **Identity Configuration**:
  - System Assigned Managed Identity
- **Admin Access**:
  - Admin groups and users can be configured via Azure AD object IDs

## Usage Notes

### Connecting Data Sources
This Grafana instance can be connected to multiple data sources:
- Azure Monitor
- Azure Log Analytics
- Prometheus
- Other supported Grafana data sources

### Creating Dashboards
After provisioning, you can create dashboards through:
- Manual configuration in the Grafana UI
- Importing existing dashboard templates
- Using the Grafana API

### Accessing Grafana
Once deployed, the Grafana instance can be accessed via its endpoint URL, which is available in the outputs. 