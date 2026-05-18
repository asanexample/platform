#!/usr/bin/env bash
set -euo pipefail

# State Migration Script: Move Terraform state blobs to new workload hierarchy paths
#
# The directory restructure changed state keys from:
#   azure/{env}/{region}/{module}/terraform.tfstate
# to:
#   azure/{env}/{region}/{workload}/{module}/terraform.tfstate
#
# This script copies state blobs to their new paths in Azure Blob Storage.
# Run this BEFORE running terragrunt in the new directory structure.
#
# Prerequisites:
#   - az CLI authenticated with access to the state storage account
#   - Storage account: tfstatemulticloud
#   - Container: terraformstate

STORAGE_ACCOUNT="tfstatemulticloud"
CONTAINER="terraformstate"
WORKLOAD="platform"

# Environments and their modules
declare -A ENV_REGIONS
ENV_REGIONS["dev"]="eastus"
ENV_REGIONS["ops"]="westus"

MODULES=(
  aks_core
  aks_identity
  aks_node_pools
  cilium
  client_config
  container_registry
  dns
  frontdoor_endpoint
  frontdoor_private_link
  frontdoor_profile
  key_vault
  log_analytics
  managed_grafana
  monitor_workspace
  naming
  networking
  prometheus_dcr
  resource_group
  storage
  storage_roles
)

# ops-only modules
OPS_ONLY_MODULES=(
  argocd
  argocd-bootstrap
)

DRY_RUN="${DRY_RUN:-true}"

echo "=== Terraform State Migration: Workload Hierarchy ==="
echo "Storage Account: ${STORAGE_ACCOUNT}"
echo "Container: ${CONTAINER}"
echo "Workload: ${WORKLOAD}"
echo "Dry Run: ${DRY_RUN}"
echo ""

migrate_blob() {
  local src="$1"
  local dst="$2"

  # Check if source blob exists
  if ! az storage blob show \
    --account-name "${STORAGE_ACCOUNT}" \
    --container-name "${CONTAINER}" \
    --name "${src}" \
    --query "name" -o tsv 2>/dev/null; then
    echo "  SKIP: Source blob does not exist: ${src}"
    return 0
  fi

  if [ "${DRY_RUN}" = "true" ]; then
    echo "  DRY RUN: Would copy ${src} -> ${dst}"
  else
    echo "  COPY: ${src} -> ${dst}"
    az storage blob copy start \
      --account-name "${STORAGE_ACCOUNT}" \
      --source-container "${CONTAINER}" \
      --source-blob "${src}" \
      --destination-container "${CONTAINER}" \
      --destination-blob "${dst}" \
      --auth-mode login
  fi
}

for env in "${!ENV_REGIONS[@]}"; do
  region="${ENV_REGIONS[$env]}"
  echo "--- ${env}/${region} ---"

  for module in "${MODULES[@]}"; do
    src="azure/${env}/${region}/${module}/terraform.tfstate"
    dst="azure/${env}/${region}/${WORKLOAD}/${module}/terraform.tfstate"
    migrate_blob "${src}" "${dst}"
  done

  # ops-only modules
  if [ "${env}" = "ops" ]; then
    for module in "${OPS_ONLY_MODULES[@]}"; do
      src="azure/${env}/${region}/${module}/terraform.tfstate"
      dst="azure/${env}/${region}/${WORKLOAD}/${module}/terraform.tfstate"
      migrate_blob "${src}" "${dst}"
    done
  fi

  echo ""
done

echo "=== Migration Complete ==="
if [ "${DRY_RUN}" = "true" ]; then
  echo ""
  echo "This was a dry run. To execute for real:"
  echo "  DRY_RUN=false ./scripts/migrate-state-to-workload-hierarchy.sh"
  echo ""
  echo "After migration, verify with:"
  echo "  cd infra/live/azure/dev/eastus/platform && terragrunt run-all plan"
  echo "  (should show 0 changes for all modules)"
fi
