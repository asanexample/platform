#!/bin/bash
# AKS deployment script
# This script runs standard terragrunt commands for AKS deployment
# The two-phase approach is no longer needed as the dependency cycle is handled by the module

set -e

# Function to display help
function show_help {
  echo "Usage: $0 [options] <directory>"
  echo ""
  echo "Options:"
  echo "  -a, --action <action> Action to perform: plan, apply, or destroy (default: plan)"
  echo "  -h, --help            Display this help message"
  echo ""
  echo "Examples:"
  echo "  $0 infra/live/azure/dev/eastus/hosting                     # Plan"
  echo "  $0 -a apply infra/live/azure/dev/eastus/hosting            # Apply"
  echo "  $0 -a destroy infra/live/azure/dev/eastus/hosting          # Destroy"
}

# Default values
ACTION="plan"
DIRECTORY=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    -a|--action)
      ACTION="$2"
      shift 2
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      if [[ -z "$DIRECTORY" ]]; then
        DIRECTORY="$1"
      else
        echo "Error: Unknown argument: $1"
        show_help
        exit 1
      fi
      shift
      ;;
  esac
done

# Validate the directory argument
if [[ -z "$DIRECTORY" ]]; then
  echo "Error: You must specify a directory."
  show_help
  exit 1
fi

if [[ ! -d "$DIRECTORY" ]]; then
  echo "Error: Directory does not exist: $DIRECTORY"
  exit 1
fi

# Validate the action argument
if [[ "$ACTION" != "plan" && "$ACTION" != "apply" && "$ACTION" != "destroy" ]]; then
  echo "Error: Invalid action: $ACTION. Must be one of: plan, apply, destroy"
  exit 1
fi

# Navigate to the specified directory
cd "$DIRECTORY"

# Clean the cache to ensure we pick up all changes
if [[ -d ".terragrunt-cache" ]]; then
  echo "Cleaning terragrunt cache..."
  rm -rf .terragrunt-cache
fi

# Initialize terragrunt
echo "Initializing terragrunt..."
terragrunt init

# Run the action
echo "Running terragrunt $ACTION..."
terragrunt "$ACTION"

# Provide completion message
if [[ "$ACTION" == "apply" ]]; then
  echo -e "\nDeployment completed successfully."
elif [[ "$ACTION" == "destroy" ]]; then
  echo -e "\nResources destroyed successfully."
fi 