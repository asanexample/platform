#!/bin/bash
set -e

# Find all *.hcl files in the _envcommon directory
echo "Finding _envcommon HCL files..."
files=$(find infra/live/azure/_envcommon -type f -name "*.hcl")

# Loop through each file
for file in $files; do
  echo "Processing $file..."
  
  # Check if file already has double-slash notation
  if grep -q "//[a-zA-Z]" "$file"; then
    echo "  File already uses double-slash notation, skipping..."
    continue
  fi
  
  # Get the module name from the file path
  filename=$(basename "$file" .hcl)
  module_path=""
  
  # Map filename to module path
  case "$filename" in
    aks_identity)
      module_path="identities"
      ;;
    aks_core)
      module_path="aks_core"
      ;;
    aks_node_pools)
      module_path="aks_node_pools"
      ;;
    cilium)
      module_path="kubernetes/cilium"
      ;;
    naming)
      module_path="naming"
      ;;
    networking)
      module_path="networking"
      ;;
    resource_group)
      module_path="resource_group"
      ;;
    key_vault)
      module_path="key_vault"
      ;;
    storage)
      module_path="storage_account"
      ;;
    *)
      echo "  Unknown module, skipping..."
      continue
      ;;
  esac
  
  echo "  Updating module path to: $module_path"
  
  # Replace the source line with double-slash notation
  sed -i '' "s|source = .*modules/azure/$module_path.*|source = \"\${find_in_parent_folders(\"infra\")}/modules/azure//$module_path\"|g" "$file"
  
  # Also update local.base_source_url if it exists
  if grep -q "base_source_url" "$file"; then
    sed -i '' 's|base_source_url = .*|base_source_url = find_in_parent_folders("infra")|g' "$file"
  fi
  
  echo "  Updated $file with double-slash notation"
done

echo "All files processed successfully!" 