#!/usr/bin/env bash
# bootstrap-iam-roles.sh — one-time break-glass apply of the iam-roles unit(s) on a from-scratch rebuild.
#
# Why this exists: the iam-roles unit CREATES PlatformDeployer (the role every other unit's provider assumes),
# so it cannot itself run via PlatformDeployer. root.hcl therefore runs iam-roles "raw" as the same-account
# profile — but the DenyTeamTagTampering SCP blocks human SSO admins from iam:TagRole, so creating the tagged
# PlatformDeployer/PlatformAdmin/... roles fails. The fix is to apply iam-roles via the SCP-EXEMPT
# OrganizationAccountAccessRole (break-glass), assumed from the management/org-master profile.
#
# Run this ONCE before `platctl bootstrap` (or before `--resume` if bootstrap already failed at iam-roles):
#   ./scripts/bootstrap-iam-roles.sh           # both envs
#   ./scripts/bootstrap-iam-roles.sh platform  # one env
# then: ./bin/platctl bootstrap --resume
#
# Prereqs: AWS SSO logged in for the management profile (org master) and each env profile. See
# docs/runbooks/platform-rebuild-from-scratch.md.
set -euo pipefail

MGMT_PROFILE="${MGMT_PROFILE:-management}"
ENVS=("${@:-platform preprod}")
# Allow a single space-joined default to split into words.
read -r -a ENVS <<<"${ENVS[*]}"

for env in "${ENVS[@]}"; do
  unit="infra/live/aws/${env}/us-east-1/platform/iam-roles"
  [ -d "$unit" ] || { echo "no iam-roles unit at $unit — skipping $env"; continue; }

  acct=$(aws sts get-caller-identity --profile "$env" --query Account --output text)
  role="arn:aws:iam::${acct}:role/OrganizationAccountAccessRole"
  echo "=== ${env} (${acct}): apply iam-roles via OrganizationAccountAccessRole (SCP-exempt) ==="

  creds=$(aws sts assume-role --role-arn "$role" --role-session-name iam-bootstrap \
    --profile "$MGMT_PROFILE" \
    --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' --output text)
  read -r aki sak st <<<"$creds"

  ( cd "$unit" && env -u AWS_PROFILE \
      AWS_ACCESS_KEY_ID="$aki" AWS_SECRET_ACCESS_KEY="$sak" AWS_SESSION_TOKEN="$st" \
      terragrunt apply -auto-approve -input=false )
  echo "=== ${env}: iam-roles applied ==="
done

echo
echo "Done. PlatformDeployer + the rest now exist. Continue with: ./bin/platctl bootstrap --resume"
