#!/bin/bash
set -e

# Use hardcoded values based on naming conventions
WORKSPACE_NAME="vip-dev-law-eus"
RESOURCE_GROUP="vip-dev-rg-eus"

# Create import commands for the three linked storage accounts
echo "Importing existing linked storage accounts into Terraform state..."
echo "Workspace: $WORKSPACE_NAME"
echo "Resource Group: $RESOURCE_GROUP"

# Import CustomLogs linked storage account
echo "Importing CustomLogs linked storage account..."
cd /Users/josh/centric/platform/infra/live/azure/dev/eastus/log_analytics
terragrunt import 'azurerm_log_analytics_linked_storage_account.this["CustomLogs"]' \
  "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.OperationalInsights/workspaces/${WORKSPACE_NAME}/linkedStorageAccounts/CustomLogs"

# Import Alerts linked storage account
echo "Importing Alerts linked storage account..."
terragrunt import 'azurerm_log_analytics_linked_storage_account.this["Alerts"]' \
  "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.OperationalInsights/workspaces/${WORKSPACE_NAME}/linkedStorageAccounts/Alerts"

# Import Query linked storage account
echo "Importing Query linked storage account..."
terragrunt import 'azurerm_log_analytics_linked_storage_account.this["Query"]' \
  "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.OperationalInsights/workspaces/${WORKSPACE_NAME}/linkedStorageAccounts/Query"

echo "Import completed. You can now run terragrunt apply"
