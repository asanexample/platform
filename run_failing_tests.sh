#!/bin/bash

# Script to run only the failing Terraform tests

set -e
EXIT_CODE=0
FAILING_TEST_DIRS=(
  "infra/tests/modules/azure/hosting"
  "infra/modules/azure/aks_core"
  "infra/modules/azure/aks_node_pools"
  "infra/modules/azure/aks_cluster_composite"
)

for dir in "${FAILING_TEST_DIRS[@]}"; do
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