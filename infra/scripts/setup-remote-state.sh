#!/bin/bash
set -e

# Fixed values for centralized state
SUBSCRIPTION_ID="9dc5edc4-8c4e-41a1-a4f8-2183c4e91954"  # Innovation-Operations subscription
TENANT_ID="c945e155-be68-4477-b8d7-01939adbfe55"
LOCATION="${AZURE_LOCATION:-eastus}"
MIGRATE=false
RESOURCE_GROUP="terraform-state-rg"
STORAGE_ACCOUNT="tfstatemulticloud"
LOG_ANALYTICS_WORKSPACE="log-terraform-state-central"

# Show help
function show_help {
  echo "Usage: $0 [options]"
  echo ""
  echo "Sets up centralized Azure remote state storage in the Innovation-Operations subscription."
  echo ""
  echo "Options:"
  echo "  -l, --location LOC      Set Azure location (default: $LOCATION)"
  echo "  -m, --migrate           Migrate existing state files (default: no)"
  echo "  -h, --help              Show this help message"
  exit 0
}

# Parse arguments
while [ "$#" -gt 0 ]; do
  case "$1" in
    -l|--location) LOCATION="$2"; shift 2 ;;
    -m|--migrate) MIGRATE=true; shift ;;
    -h|--help) show_help ;;
    *) echo "Unknown parameter: $1"; exit 1 ;;
  esac
done

# Get the root directory of the project
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "===== Setting up Centralized Azure Remote State ====="
echo "Subscription: $SUBSCRIPTION_ID (Innovation-Operations)"
echo "Location: $LOCATION"
echo "Resource Group: $RESOURCE_GROUP"
echo "Storage Account: $STORAGE_ACCOUNT"
echo "Project root: $PROJECT_ROOT"

# Check if logged in to Azure
echo -e "\nChecking Azure CLI login status..."
if ! az account show >/dev/null 2>&1; then
  echo "Not logged in to Azure. Please run 'az login' first."
  exit 1
fi

# Set subscription context
echo -e "\nSetting subscription context to Innovation-Operations..."
az account set --subscription "$SUBSCRIPTION_ID"

# Verify we're in the right subscription
CURRENT_SUB=$(az account show --query id -o tsv)
if [ "$CURRENT_SUB" != "$SUBSCRIPTION_ID" ]; then
  echo "Error: Failed to set subscription context. Current subscription: $CURRENT_SUB"
  exit 1
fi

# Ensure resource group exists
echo -e "\nChecking if resource group exists..."
if ! az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
  echo "Creating resource group '$RESOURCE_GROUP'..."
  az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --tags "Environment=Management" "Purpose=TerraformState" "ManagedBy=Script"
else
  echo "Resource group '$RESOURCE_GROUP' already exists."
fi

# Ensure storage account exists
echo -e "\nChecking if storage account exists..."
if ! az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
  echo "Creating storage account '$STORAGE_ACCOUNT'..."
  az storage account create \
    --name "$STORAGE_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --sku "Standard_LRS" \
    --kind "StorageV2" \
    --encryption-services "blob" \
    --allow-blob-public-access false \
    --min-tls-version "TLS1_2" \
    --https-only true \
    --tags "Environment=Management" "Purpose=TerraformState" "ManagedBy=Script"
else
  echo "Storage account '$STORAGE_ACCOUNT' already exists."
fi

# Set up diagnostic settings if not already configured
echo -e "\nSetting up diagnostics for storage account..."
STORAGE_ID=$(az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" --query id -o tsv)

# Check if Log Analytics workspace exists
if ! az monitor log-analytics workspace show --workspace-name "$LOG_ANALYTICS_WORKSPACE" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
  echo "Creating Log Analytics workspace '$LOG_ANALYTICS_WORKSPACE'..."
  az monitor log-analytics workspace create \
    --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --tags "Environment=Management" "Purpose=TerraformStateDiagnostics" "ManagedBy=Script"
fi

WORKSPACE_ID=$(az monitor log-analytics workspace show --workspace-name "$LOG_ANALYTICS_WORKSPACE" --resource-group "$RESOURCE_GROUP" --query id -o tsv)

# Configure diagnostics settings with correct category names
echo "Configuring diagnostic settings..."
az monitor diagnostic-settings create \
  --name "diag-terraform-state" \
  --resource "$STORAGE_ID" \
  --workspace "$WORKSPACE_ID" \
  --metrics '[{"category": "Transaction", "enabled": true}]' || echo "Diagnostics may already be configured."

# Create a single container for all state files
CONTAINER_NAME="terraformstate"

echo -e "\nCreating centralized state container..."
echo "  Checking container: $CONTAINER_NAME"

# Get storage account key
KEY=$(az storage account keys list --account-name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" --query "[0].value" -o tsv)

# Create container if it doesn't exist
if ! az storage container show --name "$CONTAINER_NAME" --account-name "$STORAGE_ACCOUNT" --account-key "$KEY" >/dev/null 2>&1; then
  echo "  Creating container: $CONTAINER_NAME"
  az storage container create \
    --name "$CONTAINER_NAME" \
    --account-name "$STORAGE_ACCOUNT" \
    --account-key "$KEY" \
    --public-access "off"
else
  echo "  Container '$CONTAINER_NAME' already exists."
fi

# Configure proper RBAC on the storage account
echo -e "\nConfiguring RBAC permissions..."
echo "Note: You need Owner or User Access Administrator role to set RBAC permissions."
echo "Assigning Storage Blob Data Contributor role to current user..."

# Assign Storage Blob Data Contributor role to the current user
CURRENT_USER=$(az ad signed-in-user show --query userPrincipalName -o tsv)
az role assignment create \
  --role "Storage Blob Data Contributor" \
  --assignee "$CURRENT_USER" \
  --scope "$STORAGE_ID" || echo "Role assignment failed or already exists. If you need this role, ask a subscription owner to assign it."

echo -e "\n===== Remote State Storage Setup Complete ====="

# If migration is requested, walk through directories and migrate state
if [ "$MIGRATE" = true ]; then
  echo -e "\n===== Migrating Existing State Files ====="
  
  # Define target directories to search for terragrunt.hcl files
  DIRS=(
    "infra/live"
  )
  
  for dir in "${DIRS[@]}"; do
    FULL_DIR="$PROJECT_ROOT/$dir"
    if [ -d "$FULL_DIR" ]; then
      echo -e "\nChecking directory: $dir"
      
      # Find all terragrunt.hcl files
      while IFS= read -r -d '' tg_file; do
        TG_DIR=$(dirname "$tg_file")
        echo -e "\nMigrating state in: ${TG_DIR#$PROJECT_ROOT/}"
        
        # Run terragrunt init with reconfigure
        (cd "$TG_DIR" && terragrunt init -reconfigure -input=false || echo "Init failed in $TG_DIR")
      done < <(find "$FULL_DIR" -name "terragrunt.hcl" -type f -print0)
    else
      echo "Directory not found: $dir"
    fi
  done
  
  echo -e "\n===== State Migration Complete ====="
fi

echo -e "\nRemote state setup completed successfully!"
echo "To use remote state in a specific component:"
echo "  cd <component_directory>"
echo "  terragrunt init -reconfigure" 