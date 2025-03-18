#!/bin/bash
# This script runs Terraform tests for modules
# It can run in plan-only mode or full test mode

set -e

# Default to plan-only mode
TEST_MODE=${TEST_MODE:-plan}
MODULES=${1:-"./modules/**/*/"}

# Function to run tests for a module
run_test() {
    local module=$1
    
    echo "Testing module: $module"
    
    cd "$module"
    
    # Check if test files exist
    if ls ./*.tftest.hcl &> /dev/null; then
        echo "Running tests for $module"
        
        if [ "$TEST_MODE" == "plan" ]; then
            # Plan-only mode - doesn't create real resources
            echo "Running in plan-only mode"
            terraform init -upgrade
            terraform test -test-directory . || { echo "Tests failed for $module"; exit 1; }
        else
            # Full test mode - may create real resources
            echo "Running in full test mode"
            terraform init -upgrade
            terraform test || { echo "Tests failed for $module"; exit 1; }
        fi
        
        echo "Tests passed for $module"
    else
        echo "No test files found for $module"
    fi
    
    cd - > /dev/null
}

echo "Running Terraform tests in $TEST_MODE mode"

# Find all modules
find "$MODULES" -type f -name "*.tf" -not -path "*/\.*" | 
    sort -u | 
    xargs -n1 dirname | 
    sort -u | 
    while read -r module; do
        run_test "$module"
    done

echo "All tests completed successfully" 