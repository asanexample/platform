#!/usr/bin/env bash
# tenant-iam-orphan-sweep.sh — delete the Crossplane-provisioned tenant IAM roles that survive a teardown so
# the tenant permissions-boundary policy can be deleted.
#
# Uninstalling Crossplane does NOT delete the EXTERNAL AWS resources its Composition created — the per-tenant
# Pod-<...> workload roles and the DeveloperAccess-<team> roles persist with the deny-escalation boundary still
# attached as their PermissionsBoundary. `aws_iam_policy.tenant_boundary` then fails to delete with:
#   DeleteConflict: Cannot delete a policy attached to entities.
# which fails the whole `crossplane` unit teardown (observed on preprod). This is the AWS-side complement to
# k8s-finalizer-clear.sh (which drains the in-cluster Crossplane CRs). Run it from a `when = destroy` provisioner
# that the boundary depends_on, so it runs BEFORE the boundary is deleted (reverse-order destroy).
#
# SAFE + precise: it deletes ONLY roles whose PermissionsBoundary == this exact boundary ARN. By the crossplane
# module's S2 condition the provisioning identity can create roles ONLY WITH this boundary attached, so every
# such role is a Composition-provisioned tenant role — exactly what a teardown should remove. The boundary is
# unique per cluster, so nothing else can match.
#
# BEST-EFFORT: always exits 0; never blocks destroy (if the roles are already gone there's nothing to do).
#
# Usage: tenant-iam-orphan-sweep.sh <boundary_policy_arn> <region> <deployer_role_arn>
set -uo pipefail

boundary="${1:?usage: tenant-iam-orphan-sweep.sh <boundary_policy_arn> <region> <deployer_role_arn>}"
region="${2:?region required}"
role_arn="${3:?role_arn required}"
export AWS_DEFAULT_REGION="$region"

# Assume the deployer role: the when=destroy provisioner runs with the unit's profile (management), but the IAM
# roles live in the workload account, so the sweep must run as the deployer (same pattern as k8s-finalizer-clear.sh).
# Best-effort: if assume-role fails, fall through on the ambient creds.
creds="$(aws sts assume-role --role-arn "$role_arn" --role-session-name tenant-iam-sweep \
  --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' --output text 2>/dev/null)"
if [ -n "$creds" ] && [ "$creds" != "None" ]; then
  read -r AKI SAK ST <<<"$creds"
  export AWS_ACCESS_KEY_ID="$AKI" AWS_SECRET_ACCESS_KEY="$SAK" AWS_SESSION_TOKEN="$ST"
  unset AWS_PROFILE
fi

# Roles carrying this boundary == the Composition-provisioned tenant roles. NOTE: `iam list-roles` omits the
# PermissionsBoundary field from its summaries, so it CANNOT be filtered on; `list-entities-for-policy` with the
# PermissionsBoundary usage filter is the correct way to find the roles a policy is a boundary for.
roles="$(aws iam list-entities-for-policy --policy-arn "$boundary" \
  --policy-usage-filter PermissionsBoundary \
  --query 'PolicyRoles[].RoleName' --output text 2>/dev/null)"

if [ -z "$roles" ] || [ "$roles" = "None" ]; then
  echo "tenant-iam-orphan-sweep: no roles carry boundary ${boundary} — nothing to sweep"
  exit 0
fi

for role in $roles; do
  # A role can't be deleted until its attached managed policies, inline policies, and instance-profile
  # memberships are removed. Detach/delete all (best-effort), then delete the role.
  for p in $(aws iam list-attached-role-policies --role-name "$role" \
    --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null); do
    aws iam detach-role-policy --role-name "$role" --policy-arn "$p" >/dev/null 2>&1 || true
  done
  for p in $(aws iam list-role-policies --role-name "$role" \
    --query 'PolicyNames[]' --output text 2>/dev/null); do
    aws iam delete-role-policy --role-name "$role" --policy-name "$p" >/dev/null 2>&1 || true
  done
  for ip in $(aws iam list-instance-profiles-for-role --role-name "$role" \
    --query 'InstanceProfiles[].InstanceProfileName' --output text 2>/dev/null); do
    aws iam remove-role-from-instance-profile --instance-profile-name "$ip" --role-name "$role" >/dev/null 2>&1 || true
  done
  if aws iam delete-role --role-name "$role" >/dev/null 2>&1; then
    echo "tenant-iam-orphan-sweep: deleted orphaned tenant role ${role}"
  else
    echo "tenant-iam-orphan-sweep: could not delete ${role} (may already be gone)"
  fi
done

exit 0
