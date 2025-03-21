#!/bin/bash
set -e

# Find all terragrunt.hcl files in the specified directory
echo "Finding terragrunt.hcl files..."
files=$(find infra/live/azure/dev/eastus -type f -name "terragrunt.hcl" -not -path "*/\.*")

# Loop through each file
for file in $files; do
  echo "Processing $file..."
  
  # Check if file already has environment variables
  if grep -q "environment = local.env" "$file"; then
    echo "  File already has environment variables, skipping..."
    continue
  fi
  
  # Use awk to add environment variables to the inputs section
  awk '
    /^inputs = {/ {
      print $0;
      print "  # Environment variables";
      print "  environment = local.env";
      print "  customer = local.customer";
      print "  prefix = local.prefix";
      print "  region_abbv = local.region_abbv";
      print "";
      next;
    }
    { print }
  ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
  
  echo "  Updated $file with environment variables"
done

echo "All files processed successfully!" 