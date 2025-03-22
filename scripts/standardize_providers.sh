#!/bin/bash

# Script to standardize provider configurations in terragrunt.hcl files
# This script will remove any custom provider configurations and ensure
# that all modules use the standard provider configurations from the root terragrunt.hcl

set -e

PLATFORM_ROOT="/Users/josh/centric/platform"
FIXED_COUNT=0
SKIPPED_COUNT=0

# Function to process a terragrunt.hcl file
process_file() {
  local file="$1"
  
  # Skip the root terragrunt.hcl file in infra directory
  if [[ "$file" == "$PLATFORM_ROOT/infra/terragrunt.hcl" ]]; then
    echo "Skipping root terragrunt.hcl file: $file"
    return
  fi
  
  # Check if the file contains a provider block to be removed
  if grep -q 'generate "provider"' "$file"; then
    echo "Fixing provider configuration in: $file"
    
    # Use sed to remove the provider configuration block
    # This pattern matches from 'generate "provider"' line through the closing brace and any whitespace after it
    sed -i'.bak' '/generate "provider"/,/^}/d' "$file"
    
    # Remove backup files
    rm -f "${file}.bak"
    
    FIXED_COUNT=$((FIXED_COUNT + 1))
  else
    echo "No custom provider configuration found in: $file"
    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
  fi
}

# Find all terragrunt.hcl files in the platform directory
echo "Finding all terragrunt.hcl files..."
TERRAGRUNT_FILES=$(find "$PLATFORM_ROOT" -name "terragrunt.hcl" -type f)
FILE_COUNT=$(echo "$TERRAGRUNT_FILES" | wc -l)

echo "Found $FILE_COUNT terragrunt.hcl files"

# Process each file
for file in $TERRAGRUNT_FILES; do
  process_file "$file"
done

echo "Configuration standardization complete!"
echo "Fixed $FIXED_COUNT files"
echo "Skipped $SKIPPED_COUNT files that didn't need fixing" 