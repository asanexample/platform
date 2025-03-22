#!/bin/bash
# This script prepares all test modules for testing by running terraform init in each test directory

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$SCRIPT_DIR/../.."
TEST_DIR="$SCRIPT_DIR/modules/azure"

echo "Preparing test modules in $TEST_DIR..."

# Function to initialize a test directory
init_test_dir() {
  local dir=$1
  if [ -d "$dir" ] && [ "$(find "$dir" -name "*.tftest.hcl" -type f | wc -l)" -gt 0 ]; then
    echo "Initializing $dir..."
    (
      cd "$dir"
      # Create empty terraform.tf file if none exists to prevent error about empty directory
      if [ ! -f main.tf ] && [ ! -f terraform.tf ]; then
        echo '# Empty terraform file to enable initialization' > terraform.tf
      fi
      terraform init -input=false -upgrade
    )
  fi
}

# Set Azure credentials for testing
source "$SCRIPT_DIR/setup_azure_credentials.sh"

# Find all test directories and initialize them
for dir in $(find "$TEST_DIR" -mindepth 1 -maxdepth 1 -type d | sort); do
  init_test_dir "$dir"
done

echo "All test modules prepared successfully." 