#!/bin/bash

# Script to run all Terraform tests in the infra/tests directory

set -e
EXIT_CODE=0
TEST_DIRS=(
  "infra/tests/modules/azure/key_vault"
  "infra/tests/modules/azure/naming"
  "infra/tests/modules/azure/networking"
  "infra/tests/modules/azure/storage_account"
  "infra/tests/modules/azure/storage_container"
  "infra/modules/azure/aks_core"
  "infra/modules/azure/aks_identity"
  "infra/modules/azure/aks_node_pools"
)

for dir in "${TEST_DIRS[@]}"; do
  if [ -d "$dir" ]; then
    echo "=== Running tests in $dir ==="
    
    # Initialize Terraform if needed
    if [ ! -d "$dir/.terraform" ]; then
      (cd "$dir" && terraform init -no-color)
    fi
    
    # Run tests
    if (cd "$dir" && terraform test -no-color); then
      echo "✅ Tests passed in $dir"
    else
      echo "❌ Tests failed in $dir"
      EXIT_CODE=1
    fi
    echo ""
  else
    echo "⚠️ Directory $dir does not exist, skipping"
  fi
done

echo "=== Test Results Summary ==="
if [ $EXIT_CODE -eq 0 ]; then
  echo "✅ All tests passed"
else
  echo "❌ Some tests failed"
fi

exit $EXIT_CODE 