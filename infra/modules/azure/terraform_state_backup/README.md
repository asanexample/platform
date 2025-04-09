# Terraform State Backup Module

This module implements an automated backup solution for Terraform state files stored in Azure Blob Storage. It creates a robust backup system with the following features:

- Secondary storage account in a different region for disaster recovery
- Automated backups using Azure Functions
- Hierarchical backup structure (daily/weekly/monthly/quarterly/yearly)
- Monitoring and alerting for backup failures
- Security controls through managed identities and RBAC
- Cost optimization with tiered storage for older backups

## Architecture

![Terraform State Backup Architecture](../../../docs/diagrams/terraform-state-backup.png)

The solution consists of these key components:

1. **Backup Storage Account**: Geo-redundant storage account in a different region from the source
2. **Azure Function**: Timer-triggered function that performs the backup operations
3. **Storage Management Policy**: Automatically moves older backups to cool/archive tiers
4. **Monitoring Alerts**: Detects backup failures and sends notifications

## Usage

```hcl
module "terraform_state_backup" {
  source = "../../modules/azure/terraform_state_backup"

  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  backup_location     = "westus"  # Different region for DR
  
  source_storage_account_name = module.terraform_state.storage_account_name
  source_storage_account_id   = module.terraform_state.storage_account_id
  source_container_name       = "terraform-state"
  
  backup_storage_account_name = "tfstatebackupdeveus"
  
  log_analytics_workspace_id = module.log_analytics.id
  alert_email                = "platform-alerts@example.com"
  
  environment = "dev"
  region_abbv = "eus"
  
  # Optional parameters
  backup_frequency    = "daily"
  daily_backup_time   = 1     # 1 AM
  backup_retention_days = 30
  
  tags = {
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| resource_group_name | The name of the resource group in which to create all resources | `string` | n/a | yes |
| location | The Azure region where the primary resources should be created | `string` | n/a | yes |
| backup_location | The Azure region where backup resources should be created (should be different from primary location) | `string` | n/a | yes |
| source_storage_account_name | The name of the storage account containing the Terraform state to back up | `string` | n/a | yes |
| source_storage_account_id | The resource ID of the storage account containing the Terraform state to back up | `string` | n/a | yes |
| source_container_name | The name of the container in the source storage account containing the Terraform state to back up | `string` | `"terraform-state"` | no |
| backup_storage_account_name | The name of the storage account for storing backups | `string` | n/a | yes |
| log_analytics_workspace_id | The resource ID of the Log Analytics workspace for monitoring | `string` | n/a | yes |
| alert_email | Email address to send alerts to | `string` | n/a | yes |
| environment | Environment name for resource naming and tagging (dev, test, prod, etc.) | `string` | `"dev"` | no |
| region_abbv | Abbreviation for region to use in resource naming | `string` | `"eus"` | no |
| backup_frequency | Frequency of backups (daily, weekly, monthly) | `string` | `"daily"` | no |
| daily_backup_time | Hour of the day to run daily backups (0-23) | `number` | `1` | no |
| weekly_backup_day | Day of the week to run weekly backups (0-6, where 0 is Sunday) | `number` | `0` | no |
| monthly_backup_day | Day of the month to run monthly backups (1-28) | `number` | `1` | no |
| backup_retention_days | Number of days to retain backup files | `number` | `30` | no |
| allowed_ip_ranges | List of IP ranges allowed to access the backup storage account | `list(string)` | `[]` | no |
| allowed_subnet_ids | List of subnet IDs allowed to access the backup storage account | `list(string)` | `[]` | no |
| application_insights_connection_string | Connection string for Application Insights | `string` | `null` | no |
| application_insights_key | Instrumentation key for Application Insights | `string` | `null` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| backup_storage_account_id | The resource ID of the backup storage account |
| backup_storage_account_name | The name of the backup storage account |
| backup_container_name | The name of the backup storage container |
| backup_function_id | The resource ID of the backup function app |
| backup_function_name | The name of the backup function app |
| backup_function_identity_id | The ID of the managed identity used by the backup function |
| backup_function_identity_principal_id | The principal ID of the managed identity used by the backup function |
| backup_action_group_id | The ID of the action group for backup alerts |
| backup_function_app_url | The URL of the backup function app |

## Backup Structure

The module implements a hierarchical backup structure:

- **Daily Backups**: Stored in `daily/YYYYMMDD/` folders
- **Weekly Backups**: Stored in `weekly/YYYY/week-WW/` folders
- **Monthly Backups**: Stored in `monthly/YYYYMM/` folders
- **Quarterly Backups**: Stored in `quarterly/YYYY/QN/` folders (automatically generated on first day of quarter)
- **Yearly Backups**: Stored in `yearly/YYYY/` folders (automatically generated on January 1st)

## Storage Lifecycle Management

The module configures the following lifecycle management for backups:

- Move to cool storage tier after 30 days
- Move to archive storage tier after 90 days
- Delete after 3 years (1095 days)
- Delete snapshots after 1 year

## Security

The module implements the following security measures:

- Uses managed identity for authentication
- Implements RBAC with least privilege
- Restricts network access to storage accounts
- Enables storage analytics and audit logging

## Monitoring and Alerting

The module includes the following monitoring and alerting capabilities:

- Backup success/failure logging to Log Analytics
- Alert on backup failures
- Alert on missing backups
- Daily backup success reporting

## Disaster Recovery

In case of a primary region outage, the backup storage account is created in a separate region with geo-redundant storage (GRS) replication. This provides protection against regional failures. 