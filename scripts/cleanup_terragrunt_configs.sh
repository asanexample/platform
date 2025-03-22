#!/bin/bash

# Script to clean up terragrunt configurations and remove common hacks and workarounds
# This script will:
# 1. Check for and fix any custom provider blocks
# 2. Ensure all terragrunt.hcl files include the root configuration properly
# 3. Standardize mock outputs to follow best practices
# 4. Clean up any deprecated or problematic configurations

set -e

PLATFORM_ROOT="/Users/josh/centric/platform"
FIXED_COUNT=0
SKIPPED_COUNT=0

# Function to process a terragrunt.hcl file
process_file() {
  local file="$1"
  local fixed=0
  
  # Skip the root terragrunt.hcl file in infra directory and cache directories
  if [[ "$file" == "$PLATFORM_ROOT/infra/terragrunt.hcl" ]] || [[ "$file" == *".terragrunt-cache"* ]]; then
    echo "Skipping file: $file"
    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
    return
  fi
  
  echo "Processing: $file"
  
  # Check 1: Custom provider blocks
  if grep -q 'generate "provider"' "$file"; then
    echo "  Fixing provider configuration..."
    sed -i'.bak' '/generate "provider"/,/^}/d' "$file"
    fixed=1
  fi
  
  # Check 2: Ensure root include is correct
  if ! grep -q 'include "root" {' "$file"; then
    echo "  Adding missing root include..."
    # Insert after locals block if it exists
    if grep -q '^}$' "$file"; then
      sed -i'.bak' '/^}$/a\
\
# Include the root terragrunt.hcl configuration\
include "root" {\
  path = find_in_parent_folders()\
}' "$file"
      fixed=1
    fi
  fi
  
  # Check 3: Proper dependency blocks with mock outputs
  if grep -q 'dependency' "$file" && ! grep -q 'mock_outputs' "$file"; then
    echo "  Warning: Dependency without mock outputs in $file"
    # This is a warning only, we don't auto-fix this as it requires domain knowledge
  fi
  
  # Check 4: Clean up obsolete skip = true blocks
  if grep -q 'skip[[:space:]]*=[[:space:]]*true' "$file"; then
    echo "  Removing obsolete skip = true configuration..."
    sed -i'.bak' '/^[[:space:]]*skip[[:space:]]*=[[:space:]]*true/d' "$file"
    fixed=1
  fi
  
  # Check 5: Ensure proper features block in provider
  if grep -q 'provider "azurerm" {' "$file" && ! grep -q 'features {' "$file"; then
    echo "  Warning: Azure provider without proper features block in $file"
    # This is a warning only as we've already standardized providers
  fi
  
  # Remove backup files
  rm -f "${file}.bak"
  
  if [ "$fixed" -eq 1 ]; then
    echo "  Fixed configurations in $file"
    FIXED_COUNT=$((FIXED_COUNT + 1))
  else
    echo "  No issues found in $file"
    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
  fi
}

# Find all terragrunt.hcl files in the platform directory
echo "Finding all terragrunt.hcl files..."
TERRAGRUNT_FILES=$(find "$PLATFORM_ROOT" -name "terragrunt.hcl" -type f | grep -v ".terragrunt-cache")
FILE_COUNT=$(echo "$TERRAGRUNT_FILES" | wc -l)

echo "Found $FILE_COUNT terragrunt.hcl files to process"

# Process each file
for file in $TERRAGRUNT_FILES; do
  process_file "$file"
done

echo "Configuration cleanup complete!"
echo "Fixed $FIXED_COUNT files"
echo "Skipped $SKIPPED_COUNT files that didn't need fixing"

# Validate terragrunt configurations
echo -e "\nValidating terragrunt configurations..."
for dir in $(find "$PLATFORM_ROOT/infra/live" -name "terragrunt.hcl" -type f | grep -v ".terragrunt-cache" | xargs dirname); do
  echo "Validating $dir"
  pushd "$dir" > /dev/null
  terragrunt validate-inputs --terragrunt-non-interactive || echo "Warning: Validation failed for $dir"
  popd > /dev/null
done

echo "Validation complete!" 