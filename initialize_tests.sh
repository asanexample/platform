#!/bin/bash

# Initialize all test directories with terraform init
# This script should be run before running the tests

set -e

# Define the test directories
TEST_DIRS=(
  "infra/tests/modules/azure/key_vault"
  "infra/tests/modules/azure/naming"
  "infra/tests/modules/azure/networking"
  "infra/tests/modules/azure/storage_account"
  "infra/tests/modules/azure/storage_container"
  "infra/tests/modules/azure/aks_core"
  "infra/tests/modules/azure/aks_identity"
  "infra/tests/modules/azure/aks_node_pools"
)

# Initialize each directory
for dir in "${TEST_DIRS[@]}"; do
  if [ -d "$dir" ]; then
    echo "=== Initializing $dir ==="
    cd "$dir"
    terraform init
    cd - > /dev/null
  else
    echo "⚠️ Directory $dir does not exist, skipping"
  fi
done

echo "=== Initialization complete ===" 