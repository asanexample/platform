#!/bin/bash
# Script to scaffold a new region from template
# This will create all the necessary configuration files for a new region

set -euo pipefail

# Styling
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"
PURPLE="\033[0;35m"
CYAN="\033[0;36m"
WHITE="\033[0;37m"
RESET="\033[0m"

# Logging
info() { 
  echo -e "${BLUE}[INFO]${RESET} $1" 
}
success() { 
  echo -e "${GREEN}[SUCCESS]${RESET} $1" 
}
warning() { 
  echo -e "${YELLOW}[WARNING]${RESET} $1" 
}
error() { 
  echo -e "${RED}[ERROR]${RESET} $1" >&2
  exit 1
}

# Check if git is available
if ! command -v git >/dev/null 2>&1; then
  error "Git is required but not installed. Please install git and try again."
fi

# Get the repository root directory
GIT_ROOT=$(git rev-parse --show-toplevel)
if [ $? -ne 0 ]; then
  error "This script must be run from within a git repository."
fi

# Default options
DRY_RUN="false"
AUTO_COMMIT="false"
AUTO_INIT="false"
VERBOSE="false"
TEMPLATES_BASE="${GIT_ROOT}/infra/live"
ALLOCATIONS_FILE="${GIT_ROOT}/allocations.csv"
SUBSCRIPTION_NAME=""

# Display usage instructions
usage() {
  cat << EOF
Usage: $(basename "$0") [options] <environment> <region> <cloud> [cidr_range]

Scaffold a new region from templates for a specific cloud provider.

Arguments:
  environment       Environment name (e.g., dev, staging, prod)
  region            Region name (e.g., westus, eastus, us-west-1)
  cloud             Cloud provider (azure, aws, gcp)
  cidr_range        CIDR range for the region (e.g., 10.0.0.0/16)
                    If not provided, it will be read from allocations.csv

Options:
  -d, --dry-run     Show what would be done without making changes
  -c, --commit      Automatically commit changes to git
  -i, --init        Automatically initialize the new region
  -v, --verbose     Display more information during execution
  -t, --templates   Specify an alternative templates directory
                    Default: ${TEMPLATES_BASE}/<cloud>/_templates
  -a, --allocations Specify an alternative allocations file
                    Default: ${ALLOCATIONS_FILE}
  -s, --subscription Specify the subscription/account name to use in the configuration
                    Default: determined by the allocations file, or blank
  -h, --help        Display this help message and exit

Examples:
  $(basename "$0") dev westus azure
  $(basename "$0") --dry-run prod us-west-1 aws
  $(basename "$0") --commit --init staging europe-west1 gcp
  $(basename "$0") --subscription "innovation-operations" dev eastus2 azure

EOF
  exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--dry-run)
      DRY_RUN="true"
      shift
      ;;
    -c|--commit)
      AUTO_COMMIT="true"
      shift
      ;;
    -i|--init)
      AUTO_INIT="true"
      shift
      ;;
    -v|--verbose)
      VERBOSE="true"
      shift
      ;;
    -t|--templates)
      TEMPLATES_BASE="$2"
      shift 2
      ;;
    -a|--allocations)
      ALLOCATIONS_FILE="$2"
      shift 2
      ;;
    -s|--subscription)
      SUBSCRIPTION_NAME="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    -*)
      error "Unknown option: $1"
      ;;
    *)
      break
      ;;
  esac
done

# Check for required arguments
if [ $# -lt 3 ]; then
  error "Missing required arguments. Run with --help for usage information."
fi

# Set variables from arguments
ENVIRONMENT=$1
TARGET_REGION=$2
CLOUD=$3
TARGET_CIDR=${4:-""}

# Validate cloud provider
case "$CLOUD" in
  azure|aws|gcp)
    # Valid cloud provider
    ;;
  *)
    error "Invalid cloud provider: $CLOUD. Supported options: azure, aws, gcp"
    ;;
esac

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  error "Invalid environment name. Must contain only alphanumeric characters, hyphens, and underscores."
fi

# Validate region name based on cloud provider
case "$CLOUD" in
  azure)
    if [[ ! "$TARGET_REGION" =~ ^[a-z0-9]+$ ]]; then
      error "Invalid Azure region name. Must contain only lowercase alphanumeric characters without hyphens."
    fi
    ;;
  aws)
    if [[ ! "$TARGET_REGION" =~ ^[a-z0-9-]+$ ]]; then
      error "Invalid AWS region name. Must contain only lowercase alphanumeric characters and hyphens."
    fi
    ;;
  gcp)
    if [[ ! "$TARGET_REGION" =~ ^[a-z0-9-]+$ ]]; then
      error "Invalid GCP region name. Must contain only lowercase alphanumeric characters and hyphens."
    fi
    ;;
esac

# Set template directory based on cloud provider
TEMPLATES_DIR="${TEMPLATES_BASE}/${CLOUD}/_templates"
if [ ! -d "${TEMPLATES_DIR}/region" ]; then
  error "Template directory not found: ${TEMPLATES_DIR}/region"
fi

# Set target directory for the new region
TARGET_DIR="${GIT_ROOT}/infra/live/${CLOUD}/${ENVIRONMENT}/${TARGET_REGION}"

# Check if the target directory already exists
if [ -d "$TARGET_DIR" ] && [ "$(ls -A "$TARGET_DIR" 2>/dev/null)" ]; then
  error "Target directory already exists and is not empty: $TARGET_DIR"
fi

# Generate region abbreviation (first letter, then first letter after each hyphen, or first 3 letters)
if [[ "$TARGET_REGION" == *"-"* ]]; then
  # Extract first letters of components (e.g., us-west-2 -> uw2)
  REGION_ABBV=$(echo "$TARGET_REGION" | sed 's/\b\([a-z]\)[^-]*/\1/g' | tr -d '-')
else
  # First 3 letters for regions without hyphens (e.g., eastus -> eas)
  REGION_ABBV=$(echo "$TARGET_REGION" | cut -c1-3)
fi

# Function to get CIDR block from allocations.csv
get_cidr_from_allocations() {
  local cloud=$1
  local region=$2
  local environment=$3
  local allocations_file=$4
  local var_name=$5
  
  # Check if allocations file exists
  if [ ! -f "$allocations_file" ]; then
    if [ "$VERBOSE" = "true" ]; then
      warning "Allocations file not found: $allocations_file"
    fi
    return 1
  fi
  
  # Convert environment to match allocations file format
  # Map dev/staging/prod to appropriate account names in allocations
  local account_prefix="innovation"
  case "$environment" in
    dev) account_name="${account_prefix}-operations" ;;
    staging|qa) account_name="${account_prefix}-test" ;;
    preprod) account_name="${account_prefix}-preprod" ;;
    prod) account_name="${account_prefix}-prod" ;;
    *) account_name="${account_prefix}-${environment}" ;;
  esac
  
  # Look for the region CIDR in the allocations file
  # The format is: Account Name,VPC Name,Cloud Provider,Region Name,Availability Zone,Region CIDR,...
  if [ "$VERBOSE" = "true" ]; then
    info "Looking for ${account_name}-${cloud},*,${cloud},${region},*,* in $allocations_file"
  fi
  
  # Use grep to find the first matching line and extract the Region CIDR (column 6)
  local cidr
  cidr=$(grep -i "${account_name}-${cloud}.*,${cloud},${region}," "$allocations_file" | head -1 | cut -d',' -f6)
  
  if [ -n "$cidr" ]; then
    # Set the value directly in the calling environment
    if [ -n "$var_name" ]; then
      eval "$var_name=\"$cidr\""
    else
      echo "$cidr"
    fi
    return 0
  fi
  
  # If we couldn't find a specific match, try a more general search
  if [ "$VERBOSE" = "true" ]; then
    warning "No exact match found, trying generic search for ${cloud},${region}"
  fi
  
  cidr=$(grep -i ",${cloud},${region}," "$allocations_file" | head -1 | cut -d',' -f6)
  
  if [ -n "$cidr" ]; then
    # Set the value directly in the calling environment
    if [ -n "$var_name" ]; then
      eval "$var_name=\"$cidr\""
    else
      echo "$cidr"
    fi
    return 0
  fi
  
  return 1
}

# Get subnet configuration from allocations.csv
get_subnet_config_from_allocations() {
  local cloud=$1
  local region=$2
  local environment=$3
  local allocations_file=$4
  local region_cidr=$5
  local var_name=$6
  
  # Check if allocations file exists
  if [ ! -f "$allocations_file" ]; then
    return 1
  fi
  
  # Convert environment to match allocations file format
  local account_prefix="innovation"
  case "$environment" in
    dev) account_name="${account_prefix}-operations" ;;
    staging|qa) account_name="${account_prefix}-test" ;;
    preprod) account_name="${account_prefix}-preprod" ;;
    prod) account_name="${account_prefix}-prod" ;;
    *) account_name="${account_prefix}-${environment}" ;;
  esac
  
  if [ "$VERBOSE" = "true" ]; then
    info "Looking for subnet configuration for ${account_name}-${cloud} in ${region} with CIDR ${region_cidr}"
  fi
  
  # Find lines matching the region and extract subnet information
  local subnet_lines
  if [ "$VERBOSE" = "true" ]; then
    info "Searching with: ${account_name}-${cloud}.*${cloud},${region}"
  fi
  
  subnet_lines=$(grep -i "${account_name}-${cloud}" "$allocations_file" | grep -i "${cloud},${region}")
  
  if [ "$VERBOSE" = "true" ]; then
    info "Found $(echo "$subnet_lines" | wc -l) matching subnet lines"
  fi
  
  if [ -z "$subnet_lines" ]; then
    # Try a more generic search if we couldn't find anything specific
    if [ "$VERBOSE" = "true" ]; then
      info "Trying more generic search: ${cloud},${region}"
    fi
    subnet_lines=$(grep -i ",${cloud},${region}," "$allocations_file")
  fi
  
  if [ -n "$subnet_lines" ]; then
    # Parse subnet information into a structure for network.hcl
    local subnet_config=""
    
    # Use a more direct approach to build the subnet configuration
    local az1_subnets=""
    local az2_subnets=""
    local az3_subnets=""
    
    # First pass to collect all subnets
    while IFS=, read -r account vpc_name cloud_name region_name az subnet_cidr vpc_cidr az_cidr subnet_cidr subnet_role usable_ips; do
      if [ "$VERBOSE" = "true" ]; then
        info "Processing subnet line: $az, $subnet_role, $subnet_cidr"
      fi
      
      # Normalize subnet name
      local subnet_name
      case "$subnet_role" in
        Kubernetes)
          subnet_name="node"
          ;;
        Services)
          subnet_name="services"
          ;;
        Endpoints)
          subnet_name="endpoints"
          ;;
        Transit)
          subnet_name="transit"
          ;;
        *)
          subnet_name=$(echo "$subnet_role" | tr '[:upper:]' '[:lower:]')
          ;;
      esac
      
      # Extract AZ number from the AZ field
      local az_num
      az_num=$(echo "$az" | grep -o -E '[0-9]+$' || echo "1")
      
      if [ "$VERBOSE" = "true" ]; then
        info "Detected AZ number: $az_num for $az"
      fi
      
      # Assign to appropriate AZ
      if [ "$az_num" = "1" ]; then
        az1_subnets="${az1_subnets}\"${subnet_name}\": \"${subnet_cidr}\", "
      elif [ "$az_num" = "2" ]; then
        az2_subnets="${az2_subnets}\"${subnet_name}\": \"${subnet_cidr}\", "
      elif [ "$az_num" = "3" ]; then
        az3_subnets="${az3_subnets}\"${subnet_name}\": \"${subnet_cidr}\", "
      else
        # If we can't determine AZ, put in AZ1 as a fallback
        az1_subnets="${az1_subnets}\"${subnet_name}\": \"${subnet_cidr}\", "
      fi
    done <<< "$subnet_lines"
    
    # Trim trailing commas
    az1_subnets=$(echo "$az1_subnets" | sed 's/, $//')
    az2_subnets=$(echo "$az2_subnets" | sed 's/, $//')
    az3_subnets=$(echo "$az3_subnets" | sed 's/, $//')
    
    # Build the complete subnet configuration
    subnet_config="{\n"
    if [ -n "$az1_subnets" ]; then
      subnet_config="${subnet_config}  \"az1\": { ${az1_subnets} }"
      if [ -n "$az2_subnets" ] || [ -n "$az3_subnets" ]; then
        subnet_config="${subnet_config},\n"
      fi
    fi
    
    if [ -n "$az2_subnets" ]; then
      subnet_config="${subnet_config}  \"az2\": { ${az2_subnets} }"
      if [ -n "$az3_subnets" ]; then
        subnet_config="${subnet_config},\n"
      fi
    fi
    
    if [ -n "$az3_subnets" ]; then
      subnet_config="${subnet_config}  \"az3\": { ${az3_subnets} }"
    fi
    
    subnet_config="${subnet_config}\n}"
    
    if [ "$VERBOSE" = "true" ]; then
      info "Generated subnet configuration: $subnet_config"
    fi
    
    # Set the value directly in the calling environment
    if [ -n "$var_name" ]; then
      eval "$var_name=\"$subnet_config\""
      return 0
    else
      echo "$subnet_config"
      return 0
    fi
  fi
  
  if [ "$VERBOSE" = "true" ]; then
    warning "No subnet configuration found in allocations file"
  fi
  return 1
}

# Calculate CIDR range if not provided
if [ -z "$TARGET_CIDR" ]; then
  # Try to get CIDR from allocations file
  if [ "$VERBOSE" = "true" ]; then
    info "Searching for CIDR in allocations file..."
  fi
  
  # Pass TARGET_CIDR as a variable name to update directly
  if get_cidr_from_allocations "$CLOUD" "$TARGET_REGION" "$ENVIRONMENT" "$ALLOCATIONS_FILE" "TARGET_CIDR"; then
    if [ "$VERBOSE" = "true" ]; then
      info "Found CIDR range in allocations file: ${TARGET_CIDR}"
    fi
  else
    # Otherwise calculate a default
    if [ "$VERBOSE" = "true" ]; then
      warning "Could not find CIDR range in allocations file, calculating default"
    fi
    
    # Convert environment to a number for the second octet
    case "$ENVIRONMENT" in
      prod) ENV_NUM=1 ;;
      staging) ENV_NUM=2 ;;
      qa) ENV_NUM=3 ;;
      dev) ENV_NUM=4 ;;
      *) ENV_NUM=5 ;;
    esac
    
    # Create a deterministic hash of the region name for the third octet
    REGION_HASH=$(( $(echo "$TARGET_REGION" | md5sum | cut -c1-2) ))
    REGION_HASH=$((16#$REGION_HASH % 256))
    
    # Construct the CIDR
    TARGET_CIDR="10.${ENV_NUM}.${REGION_HASH}.0/24"
  fi
  
  if [ "$VERBOSE" = "true" ]; then
    info "Using CIDR range: ${TARGET_CIDR}"
  fi
fi

# Create main target directory
if [ "$DRY_RUN" = "false" ]; then
  mkdir -p "$TARGET_DIR"
  info "Created directory: ${TARGET_DIR}"
else
  info "[DRY RUN] Would create directory: ${TARGET_DIR}"
fi

# Copy and update region.hcl
if [ "$DRY_RUN" = "false" ]; then
  cp "${TEMPLATES_DIR}/region/region.hcl" "${TARGET_DIR}/region.hcl"
  sed -i.bak "s/__REGION__/${TARGET_REGION}/g" "${TARGET_DIR}/region.hcl"
  sed -i.bak "s/__REGION_ABBV__/${REGION_ABBV}/g" "${TARGET_DIR}/region.hcl"
  rm "${TARGET_DIR}/region.hcl.bak" # Remove backup file created by sed
  success "Created region.hcl with region = \"${TARGET_REGION}\", region_abbv = \"${REGION_ABBV}\""
else
  info "[DRY RUN] Would create region.hcl with region = \"${TARGET_REGION}\", region_abbv = \"${REGION_ABBV}\""
fi

# Copy network.hcl template and insert target CIDR
cp_network_hcl() {
  local region_path=$1
  local region=$2
  local cidr_range=$3
  local subnet_config=$4
  local is_dry_run=$5
  
  if [ "$VERBOSE" = "true" ]; then
    info "Creating network.hcl in $region_path with CIDR $cidr_range"
    info "Subnet config: $subnet_config"
    info "Is dry run: $is_dry_run"
  fi
  
  if [ "$is_dry_run" = "true" ]; then
    success "[DRY RUN] Would create network.hcl in $region_path with CIDR $cidr_range"
    return 0
  fi
  
  # Create the network.hcl file directly with minimal formatting
  local network_file="${region_path}/network.hcl"
  
  if [ "$VERBOSE" = "true" ]; then
    info "Writing to file: $network_file"
  fi
  
  # Create a very simple network.hcl file for now
  cat > "$network_file" << EOF
# Network configuration for ${TARGET_CLOUD} ${region} region
# Generated at $(date)
# Debug info: region_path=$region_path, region=$region, cidr_range=$cidr_range

locals {
  # VNet CIDR block for this region
  address_space = ["${cidr_range}"]
  
  # Subnet configurations
  subnets = {}
}
EOF
  
  if [ -f "$network_file" ]; then
    success "Created network.hcl in $region_path with CIDR $cidr_range"
    
    # Now let's try to manually add subnet configuration if available
    if [ -n "$subnet_config" ]; then
      # Create a backup of the file
      cp "$network_file" "${network_file}.bak"
      
      # Create a temporary file with the full contents
      local temp_file=$(mktemp)
      
      cat > "$temp_file" << EOF
# Network configuration for ${TARGET_CLOUD} ${region} region
# Generated at $(date)
# Debug info: region_path=$region_path, region=$region, cidr_range=$cidr_range

locals {
  # VNet CIDR block for this region
  address_space = ["${cidr_range}"]
  
  # Subnet configurations from allocations.csv
  subnets = ${subnet_config}
}
EOF
      
      # Replace the original file with our new one
      mv "$temp_file" "$network_file"
      
      if [ "$VERBOSE" = "true" ]; then
        info "Added subnet configuration to network.hcl"
      fi
    fi
  else
    error "Failed to create network.hcl in $region_path"
  fi
}

# Generate env.hcl file
create_env_hcl() {
  local region_path=$1
  local environment=$2
  local cloud=$3
  local subscription=$4
  local is_dry_run=$5
  
  if [ "$is_dry_run" = "true" ]; then
    info "[DRY RUN] Would create env.hcl in $region_path"
    return 0
  fi
  
  # Create the env.hcl file with environment and subscription info
  cat > "${region_path}/env.hcl" << EOF
# Environment configuration for ${environment}
locals {
  env = "${environment}"
  subscription_name = "${subscription}"
  
  # Common tags
  env_tags = {
    Environment = "${environment}"
    SubscriptionName = "${subscription}"
    DataClassification = "Internal"
  }
}
EOF
  
  success "Created env.hcl in $region_path with environment = \"$environment\" and subscription = \"$subscription\""
}

# Copy all module directories
module_count=0
for module_dir in $(find "${TEMPLATES_DIR}/region" -mindepth 1 -maxdepth 1 -type d | sort); do
  module_name=$(basename "$module_dir")
  
  # Skip directories that start with underscore (like _common)
  if [[ "$module_name" == _* ]]; then
    continue
  fi
  
  # Create the target module directory
  target_module_dir="${TARGET_DIR}/${module_name}"
  
  if [ "$DRY_RUN" = "false" ]; then
    mkdir -p "$target_module_dir"
    
    # Copy all files from template module to target module
    find "$module_dir" -type f -not -path "*/\.*" | while read source_file; do
      # Get relative path from module directory
      rel_path=${source_file#$module_dir/}
      target_file="${target_module_dir}/${rel_path}"
      
      # Create directory structure if needed
      target_file_dir=$(dirname "$target_file")
      if [ ! -d "$target_file_dir" ]; then
        mkdir -p "$target_file_dir"
      fi
      
      # Copy the file (terragrunt.hcl configurations are used as is, no replacements needed)
      cp "$source_file" "$target_file"
    done
    
    success "Created module: ${module_name}"
  else
    info "[DRY RUN] Would create module: ${module_name}"
  fi
  
  module_count=$((module_count + 1))
done

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
8. aks_node_pools
9. cilium"
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

info "Total modules processed: ${module_count}"

# Git commit if requested
if [ "$AUTO_COMMIT" = "true" ] && [ "$DRY_RUN" = "false" ]; then
  info "Committing changes to git..."
  git add "${TARGET_DIR}"
  if [ -f "$ENV_HCL_PATH" ] && [ ! -f "${ENV_HCL_PATH}.bak" ]; then
    # Only commit env.hcl if we created it (i.e., it's new)
    git add "$ENV_HCL_PATH"
  fi
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

# Main execution starts here

# Process command line arguments
process_arguments "$@"

# Validate that required arguments are present
if [ -z "$TARGET_ENVIRONMENT" ] || [ -z "$TARGET_REGION" ] || [ -z "$TARGET_CLOUD" ]; then
  error "Environment, region, and cloud provider are required."
fi

# Set the templates directory based on the cloud provider
TEMPLATES_DIR="${TEMPLATES_BASE}/${TARGET_CLOUD}/_templates/region"
if [ ! -d "$TEMPLATES_DIR" ]; then
  error "Templates directory ${TEMPLATES_DIR} does not exist."
fi

# Scaffold the region
scaffold_region "$TARGET_ENVIRONMENT" "$TARGET_REGION" "$TARGET_CLOUD" "$TARGET_MODULES" "$ALL_ENVIRONMENTS" "$DRY_RUN"

# Auto-commit if requested
if [ "$AUTO_COMMIT" = "true" ] && [ "$DRY_RUN" = "false" ]; then
  # Format the commit message
  COMMIT_MESSAGE="feat(infra): scaffold ${TARGET_REGION} region for ${TARGET_CLOUD}"
  
  # Add the new files to git
  git add "infra/live/${TARGET_CLOUD}/${TARGET_ENVIRONMENT}/${TARGET_REGION}"
  
  # Commit the changes
  git commit -m "$COMMIT_MESSAGE"
  
  success "Committed changes with message: $COMMIT_MESSAGE"
fi

# Auto-initialize if requested
if [ "$AUTO_INIT" = "true" ] && [ "$DRY_RUN" = "false" ]; then
  # Run terraform init in the region directory
  pushd "infra/live/${TARGET_CLOUD}/${TARGET_ENVIRONMENT}/${TARGET_REGION}" > /dev/null
  terragrunt init
  popd > /dev/null
  
  success "Initialized region ${TARGET_REGION} for ${TARGET_CLOUD}"
fi

# Add a summary at the end
if [ "$DRY_RUN" = "true" ]; then
  info "\nDry run completed. No changes were made."
else
  info "\nSuccessfully scaffolded ${TARGET_REGION} region for ${TARGET_CLOUD}!"
  
  # Count the number of modules
  MODULE_COUNT=$(find "infra/live/${TARGET_CLOUD}/${TARGET_ENVIRONMENT}/${TARGET_REGION}" -type d -name "*" -not -path "*/\.*" | wc -l)
  info "Total modules processed: $((MODULE_COUNT - 1))"
fi

scaffold_region() {
  local environment=$1
  local region=$2
  local cloud=$3
  local modules=$4
  local all_environments=$5
  local is_dry_run=$6

  # Convert cloud to uppercase for variables
  TARGET_CLOUD=$(echo "$cloud" | tr '[:lower:]' '[:upper:]')
  
  # Set the path to the allocations.csv file
  local allocations_file="allocations.csv"
  
  # Create the region path
  local region_path="infra/live/${cloud}/${environment}/${region}"
  
  # Create the directory if it doesn't exist
  if [ ! -d "$region_path" ]; then
    if [ "$is_dry_run" = "true" ]; then
      info "[DRY RUN] Would create directory $region_path"
    else
      mkdir -p "$region_path"
      success "Created directory $region_path"
    fi
  fi
  
  # Create region.hcl with the region and region_abbr
  cp_region_hcl "$region_path" "$region" "$is_dry_run"
  
  # Generate network configuration
  local TARGET_CIDR=""
  
  # Try to get CIDR from allocations.csv
  if get_cidr_from_allocations "$cloud" "$region" "$environment" "$allocations_file" "TARGET_CIDR"; then
    if [ "$VERBOSE" = "true" ]; then
      info "Using CIDR from allocations.csv: $TARGET_CIDR"
    fi
  else
    # Use calculated CIDR if not found in allocations
    TARGET_CIDR=$(get_cidr "$region")
    if [ "$VERBOSE" = "true" ]; then
      info "Using calculated CIDR: $TARGET_CIDR"
    fi
  fi
  
  # Get subnet configuration from allocations.csv
  local SUBNET_CONFIG=""
  if get_subnet_config_from_allocations "$cloud" "$region" "$environment" "$allocations_file" "$TARGET_CIDR" "SUBNET_CONFIG"; then
    if [ "$VERBOSE" = "true" ]; then
      info "Found subnet configuration in allocations.csv"
    fi
  else
    if [ "$VERBOSE" = "true" ]; then
      warning "No subnet configuration found in allocations.csv"
    fi
  fi
  
  # Copy network.hcl template and replace placeholders
  cp_network_hcl "$region_path" "$region" "$TARGET_CIDR" "$SUBNET_CONFIG" "$is_dry_run"
  
  # Create env.hcl if it doesn't exist
  if [ ! -f "$region_path/env.hcl" ]; then
    create_env_hcl "$region_path" "$environment" "$cloud" "$SUBSCRIPTION_NAME" "$is_dry_run"
  fi

  # Generate README.md with deployment order
  if [ "$is_dry_run" = "true" ]; then
    info "[DRY RUN] Would create README.md in $region_path"
  else
    generate_readme "$region_path" "$region" "$environment" "$cloud" "$TARGET_CIDR"
    success "Created README.md in $region_path"
  fi
  
  # Create module directories
  local count=0
  if [ -z "$modules" ] || [ "$modules" = "all" ]; then
    if [ "$TARGET_CLOUD" = "AZURE" ]; then
      modules="vnet acr aks cosmosdb"
    elif [ "$TARGET_CLOUD" = "AWS" ]; then
      modules="vpc ecr eks dynamodb"
    else
      modules="network container-registry kubernetes database"
    fi
  fi
  
  for module in $modules; do
    scaffold_module "$region_path" "$module" "$is_dry_run"
    ((count++))
  done
  
  success "Successfully scaffolded region $region for $cloud with $count modules"
}