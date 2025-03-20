#!/bin/bash
# scaffold_region.sh - Script to scaffold a new region from a template
# Usage: ./scaffold_region.sh <cloud> <target_region> <environment> [OPTIONS]
# Example: ./scaffold_region.sh azure eastus dev --commit --init

set -e

# Function to display usage information
display_usage() {
  echo "Usage: $0 [--dry-run] --cloud CLOUD --target-region REGION --environment ENV --region-abbv ABBV"
  echo "  --cloud           : Cloud provider (aws|azure|gcp)"
  echo "  --target-region   : Region to scaffold (e.g., us-east-1, westus, etc.)"
  echo "  --environment     : Environment (e.g., dev, test, prod)"
  echo "  --region-abbv     : Short abbreviation for the region (e.g., east, west, use)"
  echo "  --dry-run         : Preview changes without making them"
  echo "Example: $0 --cloud azure --target-region eastus --environment dev --region-abbv east"
  exit 1
}

# Function to display script usage
function usage {
  echo "Usage: $0 <cloud> <target_region> <environment> [OPTIONS]"
  echo "Example: $0 azure eastus dev"
  echo ""
  echo "Arguments:"
  echo "  cloud         Cloud provider (azure, aws, gcp)"
  echo "  target_region Region to create (e.g., eastus, us-east-1, us-east1)"
  echo "  environment   Environment (dev, test, prod)"
  echo ""
  echo "Options:"
  echo "  --dry-run   Dry run mode - show what would be done without making changes"
  echo "  --commit    Automatically commit changes to git after scaffolding"
  echo "  --init      Automatically initialize the new region after scaffolding"
  echo "  --plan      Automatically plan the new region after scaffolding (implies --init)"
  exit 1
}

# Function to display error and exit
function error_exit {
  echo -e "\033[0;31mERROR: $1\033[0m" >&2
  exit 1
}

# Function to display success message
function success {
  echo -e "\033[0;32m$1\033[0m"
}

# Function to display info message
function info {
  echo -e "\033[0;34m$1\033[0m"
}

# Function to display warning message
function warning {
  echo -e "\033[0;33m$1\033[0m"
}

# Set defaults
DRY_RUN=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --cloud)
      CLOUD="$2"
      shift 2
      ;;
    --target-region)
      TARGET_REGION="$2"
      shift 2
      ;;
    --environment)
      ENVIRONMENT="$2"
      shift 2
      ;;
    --region-abbv)
      REGION_ABBV="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      display_usage
      ;;
  esac
done

# Validate required arguments
if [ -z "$CLOUD" ] || [ -z "$TARGET_REGION" ] || [ -z "$ENVIRONMENT" ] || [ -z "$REGION_ABBV" ]; then
  display_usage
fi

# Validate cloud provider
case "$CLOUD" in
  azure)
    VALID_REGIONS=("eastus" "eastus2" "westus" "westus2" "centralus" "northeurope" "westeurope" "southeastasia" "australiaeast" "uksouth" "canadacentral")
    ;;
  aws)
    VALID_REGIONS=("us-east-1" "us-east-2" "us-west-1" "us-west-2" "eu-west-1" "eu-central-1" "ap-southeast-1" "ap-southeast-2" "sa-east-1")
    ;;
  gcp)
    VALID_REGIONS=("us-east1" "us-central1" "us-west1" "europe-west1" "europe-west2" "asia-east1" "asia-southeast1" "australia-southeast1")
    ;;
  *)
    error_exit "Invalid cloud provider: $CLOUD. Must be one of: azure, aws, gcp"
    ;;
esac

# Validate region
REGION_VALID=false
for region in "${VALID_REGIONS[@]}"; do
  if [ "$region" = "$TARGET_REGION" ]; then
    REGION_VALID=true
    break
  fi
done

if [ "$REGION_VALID" = false ]; then
  error_exit "Invalid region '$TARGET_REGION' for cloud provider '$CLOUD'. Valid regions are: ${VALID_REGIONS[*]}"
fi

# Validate environment
case "$ENVIRONMENT" in
  dev|test|preprod|prod|demo)
    # Valid environment
    ;;
  *)
    error_exit "Invalid environment: $ENVIRONMENT. Must be one of: dev, test, preprod, prod, demo"
    ;;
esac

# Define directory paths
TEMPLATES_DIR="infra/templates/${CLOUD}"
TARGET_DIR="infra/live/${CLOUD}/${ENVIRONMENT}/${TARGET_REGION}"

# Check if template directory exists
if [ ! -d "$TEMPLATES_DIR" ]; then
  error_exit "Template directory '$TEMPLATES_DIR' does not exist."
fi

# Check if target directory already exists
if [ -d "$TARGET_DIR" ] && [ "$DRY_RUN" = "false" ]; then
  read -p "Target directory '${TARGET_DIR}' already exists. Do you want to continue and potentially overwrite files? (y/n): " CONT
  if [ "$CONT" != "y" ]; then
    info "Operation cancelled."
    exit 0
  fi
else
  if [ "$DRY_RUN" = "false" ]; then
    mkdir -p "$TARGET_DIR"
    success "Created directory: ${TARGET_DIR}"
  else
    info "[DRY RUN] Would create directory: ${TARGET_DIR}"
  fi
fi

# Function to get CIDR block for a region from allocations.csv
function get_cidr_for_region {
  local cloud=$1
  local region=$2
  local env=$3
  
  # Adjust region format if needed for looking up in the CSV
  local search_region=$(echo "$region" | tr '[:upper:]' '[:lower:]')
  local search_env=$(echo "$env" | tr '[:upper:]' '[:lower:]')
  local search_cloud=$(echo "$cloud" | tr '[:upper:]' '[:lower:]')
  
  # Set path to allocations.csv
  local allocations_file="allocations.csv"
  
  if [ -f "$allocations_file" ]; then
    # Try to find the region's CIDR in allocations.csv
    # The pattern matching needs to be adjusted based on your CSV structure
    local cidr=$(grep -i "${search_cloud}.*${search_env}.*${search_region}" "$allocations_file" | grep "Region CIDR" | head -1 | awk -F, '{print $3}')
    
    if [ -n "$cidr" ]; then
      echo "$cidr"
      return
    fi
    
    # Just log to stderr - don't include in the output
    echo "Could not find CIDR for $region in $cloud for environment $env in allocations.csv" >&2
  else
    # Just log to stderr - don't include in the output
    echo "allocations.csv file not found at $allocations_file" >&2
  fi
  
  # If we couldn't find the CIDR in the CSV or the file doesn't exist, use defaults by cloud provider
  case "$cloud" in
    azure)
      case "$region" in
        eastus) echo "10.200.0.0/21" ;;
        westus) echo "10.200.8.0/21" ;;
        *) echo "10.200.16.0/21" ;; # Default fallback for Azure
      esac
      ;;
    aws)
      case "$region" in
        us-east-1) echo "10.100.0.0/21" ;;
        us-west-2) echo "10.100.8.0/21" ;;
        *) echo "10.100.16.0/21" ;; # Default fallback for AWS
      esac
      ;;
    gcp)
      case "$region" in
        us-east1) echo "10.300.0.0/21" ;;
        us-central1) echo "10.300.8.0/21" ;;
        *) echo "10.300.16.0/21" ;; # Default fallback for GCP
      esac
      ;;
  esac
}

# Get CIDR range for the target region
TARGET_CIDR=$(get_cidr_for_region "$CLOUD" "$TARGET_REGION" "$ENVIRONMENT")

info "Cloud provider: ${CLOUD}"
info "Target region: ${TARGET_REGION} (${TARGET_CIDR})"
info "Environment: ${ENVIRONMENT}"

# Create region.hcl from template
function create_region_hcl {
  local cloud=$1
  local region=$2
  
  local region_abbv=""
  
  # Generate region abbreviation based on cloud provider's naming pattern
  case "$cloud" in
    azure)
      # For Azure, typically remove 'us' from the region name
      region_abbv=$(echo "$region" | sed 's/us//g')
      ;;
    aws)
      # For AWS, use the first letter of each segment
      region_abbv=$(echo "$region" | sed 's/-\([a-z]\)[a-z]*/\1/g')
      ;;
    gcp)
      # For GCP, similar to AWS
      region_abbv=$(echo "$region" | sed 's/-\([a-z]\)[a-z]*/\1/g')
      ;;
  esac
  
  cat << EOF
# Region-specific configuration
locals {
  region     = "${region}"
  region_abbv = "${region_abbv}"
}
EOF
}

# Create the region.hcl file
if [ "$DRY_RUN" = "false" ]; then
  cat > "${TARGET_DIR}/region.hcl" << EOF
# Region-specific configuration
locals {
  region     = "${TARGET_REGION}"
  region_abbv = "${REGION_ABBV}"
}
EOF
  success "Created ${TARGET_DIR}/region.hcl"
else
  info "[DRY RUN] Would create region.hcl with region = ${TARGET_REGION} and abbrev = ${REGION_ABBV}"
fi

# Create environment.hcl file if it doesn't exist in the target env dir
ENV_DIR="infra/live/${CLOUD}/${ENVIRONMENT}"
if [ ! -f "${ENV_DIR}/env.hcl" ] && [ "$DRY_RUN" = "false" ]; then
  mkdir -p "$ENV_DIR"
  cat << EOF > "${ENV_DIR}/env.hcl"
# Environment-specific configuration
locals {
  environment = "${ENVIRONMENT}"
}
EOF
  success "Created ${ENV_DIR}/env.hcl"
elif [ ! -f "${ENV_DIR}/env.hcl" ]; then
  info "[DRY RUN] Would create ${ENV_DIR}/env.hcl with environment configuration"
fi

# Copy env.hcl to region directory
if [ -f "${ENV_DIR}/env.hcl" ]; then
  if [ "$DRY_RUN" = "false" ]; then
    cp "${ENV_DIR}/env.hcl" "${TARGET_DIR}/env.hcl"
    success "Copied env.hcl to ${TARGET_REGION}"
  else
    info "[DRY RUN] Would copy env.hcl to ${TARGET_REGION}"
  fi
fi

# Create network.hcl with appropriate CIDR blocks
NETWORK_HCL_CONTENT=$(cat << EOF
# Network configuration for ${CLOUD} ${TARGET_REGION} region

locals {
  # VNet/VPC CIDR block for ${TARGET_REGION} region
  address_space = ["${TARGET_CIDR}"]
  
  # Subnet allocations for this region
  subnets = {
    az1 = {
      node      = cidrsubnet(local.address_space[0], 5, 0)  # /26
      services  = cidrsubnet(local.address_space[0], 6, 4)  # /27
      endpoints = cidrsubnet(local.address_space[0], 7, 10) # /28
      transit   = cidrsubnet(local.address_space[0], 8, 22) # /29
    }
    az2 = {
      node      = cidrsubnet(local.address_space[0], 5, 1)  # /26
      services  = cidrsubnet(local.address_space[0], 6, 5)  # /27
      endpoints = cidrsubnet(local.address_space[0], 7, 11) # /28
      transit   = cidrsubnet(local.address_space[0], 8, 23) # /29
    }
    az3 = {
      node      = cidrsubnet(local.address_space[0], 5, 2)  # /26
      services  = cidrsubnet(local.address_space[0], 6, 6)  # /27
      endpoints = cidrsubnet(local.address_space[0], 7, 12) # /28
      transit   = cidrsubnet(local.address_space[0], 8, 24) # /29
    }
  }
}
EOF
)

if [ "$DRY_RUN" = "false" ]; then
  echo "$NETWORK_HCL_CONTENT" > "${TARGET_DIR}/network.hcl"
  success "Created network.hcl for ${TARGET_REGION}"
else
  info "[DRY RUN] Would create network.hcl for ${TARGET_REGION} with content:"
  echo "$NETWORK_HCL_CONTENT" | head -n 10
  info "[... truncated for brevity]"
fi

# Create a terragrunt.hcl file with proper dependencies and inputs
create_module_config() {
  local module_name=$1
  local module_dir="${TARGET_DIR}/${module_name}"
  
  # Handle special case for storage modules
  if [ "$module_name" = "storage" ]; then
    actual_module_name="storage_account"
  else
    actual_module_name="$module_name"
  fi
  
  mkdir -p "$module_dir"
  
  # Define a base configuration template with locals and include blocks
  local config="# Terragrunt configuration for Azure $module_name in ${TARGET_REGION} region

# Local variables for this configuration
locals {
  # Load common variables
  common_vars = read_terragrunt_config(find_in_parent_folders(\"common.hcl\"))
  
  # Extract commonly used variables
  env          = local.common_vars.locals.env
  prefix       = local.common_vars.locals.prefix
  customer     = local.common_vars.locals.customer
  region       = \"${TARGET_REGION}\"
  region_abbv  = \"${REGION_ABBV}\"
  tags         = local.common_vars.locals.tags
}

# Include the root terragrunt.hcl configuration
include \"root\" {
  path = find_in_parent_folders()
}

# Use the ${module_name} module
terraform {
  source = \"\${get_repo_root()}/infra/modules/${CLOUD}/${actual_module_name}\"
}
"

  # Add module-specific dependencies and inputs
  case "$module_name" in
    "naming")
      config+="# Specify inputs specific to this module
inputs = {
  # Naming components
  prefix      = local.prefix
  customer    = local.customer
  environment = local.env
  region_abbv = local.region_abbv
}
"
      ;;
    "resource_group")
      config+="# Set dependencies for this module
dependency \"naming\" {
  config_path = \"../naming\"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    resource_group = \"mock-rg\"
  }
}

# Specify inputs specific to this module
inputs = {
  name     = dependency.naming.outputs.resource_group
  location = local.region
  tags     = local.tags
}
"
      ;;
    "networking")
      # Use a completely rewritten template for networking module
      config="# Terragrunt configuration for Azure $module_name in ${TARGET_REGION} region

# Local variables for this configuration
locals {
  # Load common variables
  common_vars = read_terragrunt_config(find_in_parent_folders(\"common.hcl\"))
  
  # Extract commonly used variables
  env          = local.common_vars.locals.env
  prefix       = local.common_vars.locals.prefix
  customer     = local.common_vars.locals.customer
  region       = \"${TARGET_REGION}\"
  region_abbv  = \"${REGION_ABBV}\"
  tags         = local.common_vars.locals.tags
  
  # Load network configuration from network.hcl
  network_vars = read_terragrunt_config(find_in_parent_folders(\"network.hcl\"))
  address_space = local.network_vars.locals.address_space
  subnets       = local.network_vars.locals.subnets
}

# Include the root terragrunt.hcl configuration
include \"root\" {
  path = find_in_parent_folders()
}

# Use the ${module_name} module
terraform {
  source = \"\${get_repo_root()}/infra/modules/${CLOUD}/${actual_module_name}\"
}

# Set dependencies for this module
dependency \"resource_group\" {
  config_path = \"../resource_group\"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    name = \"mock-rg\"
  }
}

dependency \"naming\" {
  config_path = \"../naming\"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    virtual_network = \"mock-vnet\"
  }
}

# Specify inputs specific to this module
inputs = {
  resource_group_name = dependency.resource_group.outputs.name
  location            = local.region
  vnet_name           = dependency.naming.outputs.virtual_network
  address_space       = local.address_space
  subnets = {
    az1-kubernetes = {
      address_prefixes = [local.subnets.az1.node]
      service_endpoints = [\"Microsoft.Storage\", \"Microsoft.KeyVault\"]
    }
    az1-services = {
      address_prefixes = [local.subnets.az1.services]
      service_endpoints = [\"Microsoft.Storage\", \"Microsoft.KeyVault\"]
    }
    az1-endpoints = {
      address_prefixes = [local.subnets.az1.endpoints]
      service_endpoints = [\"Microsoft.Storage\", \"Microsoft.KeyVault\"]
    }
  }
  tags                = local.tags
}
"
      ;;
    "key_vault")
      config+="# Set dependencies for this module
dependency \"resource_group\" {
  config_path = \"../resource_group\"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    name = \"mock-rg\"
  }
}

dependency \"naming\" {
  config_path = \"../naming\"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    key_vault = \"mock-kv\"
  }
}

# Specify inputs specific to this module
inputs = {
  resource_group_name = dependency.resource_group.outputs.name
  location            = local.region
  key_vault_name      = dependency.naming.outputs.key_vault
  tags                = local.tags
}
"
      ;;
    "storage")
      config+="# Set dependencies for this module
dependency \"resource_group\" {
  config_path = \"../resource_group\"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    name = \"mock-rg\"
  }
}

dependency \"naming\" {
  config_path = \"../naming\"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    storage_account = \"mockstorageacct\"
  }
}

# Specify inputs specific to this module
inputs = {
  resource_group_name  = dependency.resource_group.outputs.name
  location             = local.region
  storage_account_name = dependency.naming.outputs.storage_account
  tags                 = local.tags
}
"
      ;;
    "aks_identity")
      config+="# Set dependencies for this module
dependency \"resource_group\" {
  config_path = \"../resource_group\"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    name = \"mock-rg\"
  }
}

dependency \"naming\" {
  config_path = \"../naming\"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    aks_identity = \"mock-identity\"
    aks_cluster = \"mock-aks\"
  }
}

# Specify inputs specific to this module
inputs = {
  resource_group_name = dependency.resource_group.outputs.name
  location            = local.region
  identity_name       = dependency.naming.outputs.aks_identity
  cluster_name        = dependency.naming.outputs.aks_cluster
  tags                = local.tags
}
"
      ;;
    "aks_core")
      config+="# Set dependencies for this module
dependency \"resource_group\" {
  config_path = \"../resource_group\"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    name = \"mock-rg\"
  }
}

dependency \"naming\" {
  config_path = \"../naming\"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    aks_cluster = \"mock-aks\"
  }
}

dependency \"networking\" {
  config_path = \"../networking\"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    subnet_ids = { 
      \"az1-kubernetes\" = \"/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Network/virtualNetworks/mock-vnet/subnets/az1-kubernetes\"
    }
  }
}

dependency \"aks_identity\" {
  config_path = \"../aks_identity\"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    id = \"/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/mock-identity\"
  }
}

# Specify inputs specific to this module
inputs = {
  resource_group_name = dependency.resource_group.outputs.name
  location            = local.region
  cluster_name        = dependency.naming.outputs.aks_cluster
  kubernetes_version  = \"1.32\"
  identity_type       = \"UserAssigned\"
  user_assigned_identity_id = dependency.aks_identity.outputs.id
  subnet_id           = dependency.networking.outputs.subnet_ids[\"az1-kubernetes\"]
  prefix              = local.prefix
  environment         = local.env
  region_abbv         = local.region_abbv
  customer            = local.customer
  sku_tier            = \"Standard\"
  local_account_disabled = true
  workload_identity_enabled = true
  oidc_issuer_enabled = true
  
  # Azure AD integration config (required for Kubernetes ≥ 1.25 with local_account_disabled)
  azure_active_directory_role_based_access_control = {
    managed                = true
    admin_group_object_ids = [\"00000000-0000-0000-0000-000000000000\"]
    azure_rbac_enabled     = true
    tenant_id              = null
  }
  default_nodepool_node_labels = {
    \"nodepool-type\" = \"system\"
    \"environment\"   = local.env
    \"region\"        = local.region
  }
  network_plugin     = \"azure\"
  network_policy     = \"azure\"
  service_cidr       = \"10.0.0.0/16\"
  dns_service_ip     = \"10.0.0.10\"
  tags               = local.tags
}
"
      ;;
    "aks_node_pools")
      config+="# Set dependencies for this module
dependency \"aks_core\" {
  config_path = \"../aks_core\"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    id = \"/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.ContainerService/managedClusters/mock-aks\"
    name = \"mock-aks\"
  }
}

# Add dependency for resource group
dependency \"resource_group\" {
  config_path = \"../resource_group\"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    name = \"mock-rg\"
  }
}

# Specify inputs specific to this module
inputs = {
  prefix       = local.prefix
  customer     = local.customer
  environment  = local.env
  region_abbv  = local.region_abbv
  
  # Use the actual ID from the AKS cluster output
  aks_cluster_id = dependency.aks_core.outputs.id
  
  app_node_pool_enabled = true
  app_node_pool_vm_size = \"Standard_D4s_v3\"
  app_node_pool_enable_auto_scaling = true
  app_node_pool_min_count = 2
  app_node_pool_max_count = 5
  app_node_pool_os_disk_size_gb = 128
  app_node_pool_os_disk_type = \"Managed\"
  app_node_pool_max_pods = 30
  app_node_pool_node_labels = {
    \"nodepool-type\" = \"app\"
    \"environment\" = local.env
    \"region\" = local.region
  }
  
  tags = local.tags
}
"
      ;;
    *)
      # Generic module configuration
      config+="# Set dependencies for this module
# (Add module-specific dependencies here)

# Specify inputs specific to this module
inputs = {
  # Default values will be populated when the module is implemented
}
"
      ;;
  esac
  
  if [ "$DRY_RUN" = "false" ]; then
    echo "$config" > "${module_dir}/terragrunt.hcl"
    success "Created and updated module: ${module_name}"
  else
    info "[DRY RUN] Would create config for module: ${module_name}"
  fi
}

# Create a terragrunt.hcl file for a module in the target directory (simple version for backward compatibility)
create_terragrunt() {
  local module_name=$1
  local module_dir="${TARGET_DIR}/${module_name}"
  
  # Handle special case for storage modules
  if [ "$module_name" = "storage" ]; then
    actual_module_name="storage_account"
  else
    actual_module_name="$module_name"
  fi
  
  mkdir -p "$module_dir"
  
  cat > "${module_dir}/terragrunt.hcl" << EOF
# terragrunt.hcl for ${module_name} in ${TARGET_REGION} (${CLOUD})
include {
  path = find_in_parent_folders()
}

dependencies {
  paths = []
}

terraform {
  source = "\${get_repo_root()}/infra/modules/${CLOUD}/${actual_module_name}"
}

inputs = {
  # Default values will be populated when the module is implemented
}
EOF

  if [ "$DRY_RUN" = "false" ]; then
    success "Created simple module: ${module_name}"
  else
    info "[DRY RUN] Would create simple module: ${module_name}"
  fi
}

# Copy template modules to the target directory
module_count=0
if [ -d "${TEMPLATES_DIR}/modules" ]; then
  find "${TEMPLATES_DIR}/modules" -mindepth 1 -maxdepth 1 -type d | while read template_module_dir; do
    module_name=$(basename "$template_module_dir")
    
    # Skip directories that start with underscore (like _common)
    if [[ "$module_name" == _* ]]; then
      continue
    fi
    
    # Create the target module directory
    target_module_dir="${TARGET_DIR}/${module_name}"
    
    if [ "$DRY_RUN" = "false" ]; then
      mkdir -p "$target_module_dir"
      
      # Copy all files from template module to target module
      find "$template_module_dir" -type f -not -path "*/\.*" | while read source_file; do
        # Get relative path from module directory
        rel_path=${source_file#$template_module_dir/}
        target_file="${target_module_dir}/${rel_path}"
        
        # Create directory structure if needed
        target_file_dir=$(dirname "$target_file")
        if [ ! -d "$target_file_dir" ]; then
          mkdir -p "$target_file_dir"
        fi
        
        # Copy the file and replace placeholders
        cp "$source_file" "$target_file"
        
        # Replace placeholders in the file
        sed -i.bak "s/__REGION__/${TARGET_REGION}/g" "$target_file"
        sed -i.bak "s/__ENVIRONMENT__/${ENVIRONMENT}/g" "$target_file"
        sed -i.bak "s/__CLOUD__/${CLOUD}/g" "$target_file"
        sed -i.bak "s/__CIDR_RANGE__/${TARGET_CIDR//\//\\/}/g" "$target_file"
        rm "${target_file}.bak" # Remove backup file created by sed
      done
      
      create_module_config "$module_name"
    else
      info "[DRY RUN] Would create and update module: ${module_name}"
    fi
    
    module_count=$((module_count + 1))
  done
fi

# If no template modules are found, create basic module directories
if [ "$module_count" -eq 0 ]; then
  # Define standard modules based on cloud provider
  STANDARD_MODULES=""
  case "$CLOUD" in
    azure)
      STANDARD_MODULES="resource_group naming networking key_vault storage aks_identity aks_core aks_node_pools"
      ;;
    aws)
      STANDARD_MODULES="vpc subnets security_groups s3 eks_cluster eks_node_groups"
      ;;
    gcp)
      STANDARD_MODULES="vpc subnets firewall_rules storage gke_cluster gke_node_pools"
      ;;
  esac
  
  for module in $STANDARD_MODULES; do
    if [ "$DRY_RUN" = "false" ]; then
      mkdir -p "${TARGET_DIR}/${module}"
      create_module_config "$module"
    else
      info "[DRY RUN] Would create empty module directory: ${module}"
    fi
    
    module_count=$((module_count + 1))
  done
fi

# Create a README.md file for the new region
if [ "$DRY_RUN" = "false" ]; then
  # Determine standard module list based on cloud provider
  DEPLOYMENT_ORDER=""
  case "$CLOUD" in
    azure)
      DEPLOYMENT_ORDER="1. resource_group
2. naming
3. networking
4. key_vault
5. storage
6. aks_identity
7. aks_core
8. aks_node_pools"
      ;;
    aws)
      DEPLOYMENT_ORDER="1. vpc
2. subnets
3. security_groups
4. s3
5. eks_cluster
6. eks_node_groups"
      ;;
    gcp)
      DEPLOYMENT_ORDER="1. vpc
2. subnets
3. firewall_rules
4. storage
5. gke_cluster
6. gke_node_pools"
      ;;
  esac
  
  # Create README content
  README_CONTENT="# ${TARGET_REGION} Region Infrastructure (${CLOUD})

This directory contains the infrastructure configuration for the ${TARGET_REGION} region in the ${ENVIRONMENT} environment for ${CLOUD}.

## Modules

The following modules are deployed in this region:"
  
  # Add module list
  for module_dir in $(find "${TARGET_DIR}" -mindepth 1 -maxdepth 1 -type d -not -path "*/\.*" | sort); do
    module_name=$(basename "$module_dir")
    if [[ "$module_name" != _* ]]; then
      README_CONTENT="${README_CONTENT}
- \`${module_name}\`"
    fi
  done
  
  # Add CIDR range and deployment order
  README_CONTENT="${README_CONTENT}

## CIDR Range

The ${TARGET_REGION} region uses the CIDR range: \`${TARGET_CIDR}\`

## Deployment Order

Modules should be deployed in the following order:

${DEPLOYMENT_ORDER}

## Generated Configuration

This directory was scaffolded from templates on $(date)."

  # Write to file
  echo "$README_CONTENT" > "${TARGET_DIR}/README.md"
  success "Created README.md for ${TARGET_REGION}"
else
  info "[DRY RUN] Would create README.md for ${TARGET_REGION} with standard deployment information"
fi

if [ "$DRY_RUN" = "false" ]; then
  info "\nSuccessfully scaffolded ${TARGET_REGION} region for ${CLOUD}!"
else
  info "\n[DRY RUN] Would scaffold ${TARGET_REGION} region for ${CLOUD}"
fi

info "Total modules to process: ${module_count}"

# Git commit if requested
if [ "$AUTO_COMMIT" = "true" ] && [ "$DRY_RUN" = "false" ]; then
  info "Committing changes to git..."
  git add "${TARGET_DIR}"
  git commit -m "feat(infra): scaffold ${CLOUD} ${TARGET_REGION} region" -m "- Automated scaffolding of ${TARGET_REGION} region configuration" -m "- For ${CLOUD} in ${ENVIRONMENT} environment" -m "- Includes standard modules and configuration"
  success "Changes committed to git"
fi

# Initialize the new region if requested
if [ "$AUTO_INIT" = "true" ] && [ "$DRY_RUN" = "false" ]; then
  info "Initializing the new region..."
  cd $(git rev-parse --show-toplevel) # Change to repo root
  make init-region ENV=${ENVIRONMENT} REGION=${TARGET_REGION} CLOUD=${CLOUD}
  success "Initialization complete"
fi

# Plan the new region if requested
if [ "$AUTO_PLAN" = "true" ] && [ "$DRY_RUN" = "false" ]; then
  info "Planning the new region..."
  cd $(git rev-parse --show-toplevel) # Change to repo root
  make plan-region ENV=${ENVIRONMENT} REGION=${TARGET_REGION} CLOUD=${CLOUD}
  success "Planning complete"
fi

if [ "$DRY_RUN" = "false" ]; then
  info "Next steps:"
  if [ "$AUTO_INIT" = "false" ]; then
    info "1. Initialize the new region: make init-region ENV=${ENVIRONMENT} REGION=${TARGET_REGION} CLOUD=${CLOUD}"
  fi
  if [ "$AUTO_PLAN" = "false" ]; then
    info "2. Plan the new region: make plan-region ENV=${ENVIRONMENT} REGION=${TARGET_REGION} CLOUD=${CLOUD}"
  fi
  info "3. Review the generated files and make any necessary adjustments"
  info "4. Apply the infrastructure: make apply-region ENV=${ENVIRONMENT} REGION=${TARGET_REGION} CLOUD=${CLOUD}"
else
  info "To execute for real, run the command without --dry-run flag"
fi

# Check if template directories exist and provide suggestions if not
if [ ! -d "${TEMPLATES_DIR}/modules" ] && [ "$DRY_RUN" = "false" ]; then
  warning "\nNotice: No template modules found at ${TEMPLATES_DIR}/modules"
  info "Consider creating templates for better scaffolding."
  info "Suggested template structure:"
  info "infra/templates/${CLOUD}/modules/<module_name>/"
  info "With placeholder variables like __REGION__, __ENVIRONMENT__, and __CIDR_RANGE__"
fi 