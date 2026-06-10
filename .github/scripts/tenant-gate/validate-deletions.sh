#!/usr/bin/env bash
# Tenant Claims Gate — deprovisioning guard (ADR-062, #283). A claim REMOVAL hard-deletes the tenant
# (ArgoCD prune → Crossplane tears down the namespace; ECR is retained via deletionPolicy: Orphan). To make a
# one-shot destroy-of-active impossible, a claim may only be deleted if it was first put into the
# `decommissioning` grace state (a separate, reversible PR). The deleted file still exists on the BASE
# checkout with its last committed phase, so we read it from there.
#
# Env in: BASE_DIR, CLAIM_DELETED_FILES (space-separated paths, relative)
# Requires: yq.
set -euo pipefail

: "${BASE_DIR:?}"
CLAIM_DELETED_FILES="${CLAIM_DELETED_FILES:-}"

fail() { echo "::error::tenant-gate(deprovision): $*" >&2; exit 1; }

for claim in $CLAIM_DELETED_FILES; do
  f="${BASE_DIR}/${claim}"
  # A file deleted in this PR is present on BASE. If it isn't (e.g. already gone), nothing to guard.
  [ -f "$f" ] || continue
  phase="$(yq '.spec.lifecycle.phase // "active"' "$f")"
  [ "$phase" = "decommissioning" ] || fail "${claim}: cannot delete an active tenant. Set spec.lifecycle.phase: decommissioning first (the Deprovision template, or a claim edit), let that merge and the grace window pass, THEN remove the claim. This guarantees a reversible window (ADR-062)."
  echo "   ${claim}: decommissioning on base — delete permitted"
done

echo "tenant-gate: claim deletions are decommission-first"
