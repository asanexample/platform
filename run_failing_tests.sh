#!/bin/bash

# Script to run specific failing Terraform tests
# Usage: ./run_failing_tests.sh test1 test2 test3
# Example: ./run_failing_tests.sh "infra/tests/modules/azure/aks_core"

set -e
EXIT_CODE=0

# If no arguments provided, run these known failing tests
if [ $# -eq 0 ]; then
  TEST_DIRS=(
    "infra/tests/modules/azure/aks_core"
  )
else
  # Use the tests provided as arguments
  TEST_DIRS=("$@")
fi

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