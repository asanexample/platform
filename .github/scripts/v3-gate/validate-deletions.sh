#!/usr/bin/env bash
# v3 gitops gate — deprovisioning guard (ADR-062 #283, the v3 successor to the Tenant Claims Gate's
# validate-deletions.sh). Removing an Environment claim hard-deletes the Environment (ArgoCD prune → Crossplane
# tears down the namespace; ECR is retained via deletionPolicy: Orphan). To make a one-shot destroy-of-active
# impossible, an Environment claim may only be deleted if it was first put into the `decommissioning` grace
# state (a separate, reversible PR — the Deprovision template). The deleted file still exists on the BASE
# checkout with its last committed phase, so we read it from there.
#
# Scope: only gitops/environments/** deletions are decommission-first guarded (Products carry no lifecycle).
# Product deletions are not blocked here — they are admin-approval-gated by the gate's commit status, the same
# as any deletion. (A Product should have no remaining Environments before removal; enforcing that completeness
# is a follow-up.)
#
# Env in: BASE_DIR, DELETED_FILES (space-separated registry paths, relative — products + environments)
# Requires: yq.
set -euo pipefail

: "${BASE_DIR:?}"
DELETED_FILES="${DELETED_FILES:-}"

fail() { echo "::error::v3-gate(deprovision): $*" >&2; exit 1; }

guarded=0
for f in $DELETED_FILES; do
  # Only Environment claims are decommission-first guarded.
  case "$f" in
    gitops/environments/*) ;;
    *) continue ;;
  esac
  base="${BASE_DIR}/${f}"
  # A file deleted in this PR is present on BASE. If it isn't (e.g. already gone), nothing to guard.
  [ -f "$base" ] || continue
  phase="$(yq '.spec.lifecycle.phase // "active"' "$base")"
  [ "$phase" = "decommissioning" ] || fail "${f}: cannot delete an active Environment. Set spec.lifecycle.phase: decommissioning first (the Deprovision template, or a claim edit), let that merge and the grace window pass, THEN remove the claim — guaranteeing a reversible window (ADR-062 #283)."
  echo "   ${f}: decommissioning on base — delete permitted"
  guarded=$((guarded + 1))
done

echo "v3-gate: ${guarded} Environment deletion(s) are decommission-first"
