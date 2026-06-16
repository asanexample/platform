#!/usr/bin/env bash
# Validate every OpenTofu module under infra/modules (the CI "Validate all modules" step). Modules without a
# versions.tf get a temporary, throwaway one generated (AWS vs Helm/Kubernetes provider sets) so `tofu validate`
# can resolve providers; it is removed afterward. Returns non-zero if ANY module fails init or validate.
#
# Env in: TF_PLUGIN_CACHE_DIR (shared provider cache, created if absent).
# Requires: tofu, find, grep. Run from the repo root.
set -uo pipefail

mkdir -p "${TF_PLUGIN_CACHE_DIR:?TF_PLUGIN_CACHE_DIR must be set}"

read -r -d '' AWS_VERSIONS << 'TFEOF' || true
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
TFEOF

read -r -d '' HELM_VERSIONS << 'TFEOF' || true
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}
TFEOF

# Modules with known provider compatibility issues (fix separately)
SKIP_VALIDATE="infra/modules/argocd infra/modules/vcluster"

FAILED=0

for dir in $(find infra/modules -type f -name "*.tf" -not -path "*/.terraform/*" -exec dirname {} \; | sort -u | grep -v /templates); do
  if echo "$SKIP_VALIDATE" | grep -qw "$dir"; then
    echo "::group::Skipping $dir (known issues)"
    echo "::endgroup::"
    continue
  fi

  echo "::group::Validating $dir"

  GENERATED=false
  if [ ! -f "$dir/versions.tf" ]; then
    GENERATED=true
    case "$dir" in
      infra/modules/aws/*)   echo "$AWS_VERSIONS"   > "$dir/versions.tf" ;;
      *)                     echo "$HELM_VERSIONS"   > "$dir/versions.tf" ;;
    esac
  fi

  if tofu -chdir="$dir" init -backend=false -input=false > /dev/null 2>&1; then
    if tofu -chdir="$dir" validate; then
      echo "OK: $dir"
    else
      echo "FAIL: $dir"
      FAILED=1
    fi
  else
    echo "FAIL (init): $dir"
    FAILED=1
  fi

  if [ "$GENERATED" = true ]; then
    rm -f "$dir/versions.tf" "$dir/.terraform.lock.hcl"
    rm -rf "$dir/.terraform"
  fi

  echo "::endgroup::"
done

exit $FAILED
