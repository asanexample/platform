#!/bin/bash
# This script extracts Azure subscription and tenant IDs and saves them for Terraform tests

# Exit on error
set -e

echo "Checking Azure CLI login status..."
if ! az account show >/dev/null 2>&1; then
  echo "You are not logged in to Azure CLI. Please run 'az login' first."
  exit 1
fi

# Extract subscription and tenant IDs
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)

echo "Using Azure subscription: $(az account show --query name -o tsv) ($SUBSCRIPTION_ID)"
echo "Tenant ID: $TENANT_ID"

# Create a terraform.tfvars file in the test directory
cat > "$(dirname "$0")/terraform.tfvars" << EOL
# Terraform variables for tests
# Generated on $(date) by setup_azure_credentials.sh
# This file is excluded from version control in .gitignore

subscription_id = "$SUBSCRIPTION_ID"
tenant_id       = "$TENANT_ID"
EOL

# Also export environment variables for immediate use
export TF_VAR_subscription_id="$SUBSCRIPTION_ID"
export TF_VAR_tenant_id="$TENANT_ID"

echo "Created terraform.tfvars with your current Azure credentials."
echo "Environment variables TF_VAR_subscription_id and TF_VAR_tenant_id have been set."
echo "These values are excluded from version control in .gitignore" 