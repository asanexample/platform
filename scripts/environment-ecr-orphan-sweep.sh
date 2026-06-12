#!/usr/bin/env bash
# tenant-ecr-orphan-sweep.sh — delete the Crossplane-provisioned tenant ECR repos (team-<team>/<app>) that
# survive a teardown. Sibling of tenant-iam-orphan-sweep.sh: uninstalling Crossplane does not delete the
# EXTERNAL AWS resources its Composition created, so the cross-account ECR repos in the platform account orphan.
# They don't BLOCK teardown (and a rebuild re-adopts them by external-name), but a clean teardown should remove
# them so each cycle starts from a pristine slate.
#
# The repos live in the PLATFORM account. Assume the given role there — the platform PlatformDeployer, which the
# teardown's (management) profile can assume — and force-delete every team-* repository. ALL team-* repos are
# tenant repos: the platform/ecr unit deliberately does not manage them (they're Composition-owned).
#
# BEST-EFFORT: always exits 0; never blocks destroy.
#
# Usage: tenant-ecr-orphan-sweep.sh <sweep_role_arn> <region>
set -uo pipefail

role_arn="${1:?usage: tenant-ecr-orphan-sweep.sh <sweep_role_arn> <region>}"
region="${2:?region required}"
export AWS_DEFAULT_REGION="$region"

# Assume the cross-account sweep role (platform PlatformDeployer). Best-effort: fall through on ambient creds.
creds="$(aws sts assume-role --role-arn "$role_arn" --role-session-name tenant-ecr-sweep \
  --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' --output text 2>/dev/null)"
if [ -n "$creds" ] && [ "$creds" != "None" ]; then
  read -r AKI SAK ST <<<"$creds"
  export AWS_ACCESS_KEY_ID="$AKI" AWS_SECRET_ACCESS_KEY="$SAK" AWS_SESSION_TOKEN="$ST"
  unset AWS_PROFILE
fi

repos="$(aws ecr describe-repositories \
  --query "repositories[?starts_with(repositoryName,'team-')].repositoryName" \
  --output text 2>/dev/null)"

if [ -z "$repos" ] || [ "$repos" = "None" ]; then
  echo "tenant-ecr-orphan-sweep: no team-* repositories — nothing to sweep"
  exit 0
fi

for repo in $repos; do
  # --force deletes the repo even though it holds images (the tenant app images, gone on a full teardown).
  if aws ecr delete-repository --repository-name "$repo" --force >/dev/null 2>&1; then
    echo "tenant-ecr-orphan-sweep: deleted orphaned tenant repo ${repo}"
  else
    echo "tenant-ecr-orphan-sweep: could not delete ${repo} (may already be gone)"
  fi
done

exit 0
