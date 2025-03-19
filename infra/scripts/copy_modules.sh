#!/bin/bash
# Script to copy module dependencies for terragrunt

# Get the absolute path to the repository root
REPO_ROOT=$(git rev-parse --show-toplevel)

# Target directory is the current directory
TARGET_DIR="$(pwd)/.terraform-cache"

# Create target directories
mkdir -p "$TARGET_DIR/modules"

# Copy all required modules
echo "Copying modules to $TARGET_DIR"
mkdir -p "$TARGET_DIR/naming"
cp -R "$REPO_ROOT/infra/modules/azure/naming"/* "$TARGET_DIR/naming/"

mkdir -p "$TARGET_DIR/networking"
cp -R "$REPO_ROOT/infra/modules/azure/networking"/* "$TARGET_DIR/networking/"

mkdir -p "$TARGET_DIR/storage_account"
cp -R "$REPO_ROOT/infra/modules/azure/storage_account"/* "$TARGET_DIR/storage_account/"

mkdir -p "$TARGET_DIR/key_vault"
cp -R "$REPO_ROOT/infra/modules/azure/key_vault"/* "$TARGET_DIR/key_vault/"

mkdir -p "$TARGET_DIR/aks_cluster_composite"
cp -R "$REPO_ROOT/infra/modules/azure/aks_cluster_composite"/* "$TARGET_DIR/aks_cluster_composite/"

# Create symlinks in the .terraform directory to make paths work
cd .terraform
ln -sf ../../../.terraform-cache/naming naming
ln -sf ../../../.terraform-cache/networking networking
ln -sf ../../../.terraform-cache/storage_account storage_account
ln -sf ../../../.terraform-cache/key_vault key_vault
ln -sf ../../../.terraform-cache/aks_cluster_composite aks_cluster_composite

echo "Module dependencies copied successfully" 