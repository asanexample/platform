#!/usr/bin/env bash
# v3 gitops gate — deprovisioning guard (ADR-062 #283, the v3 successor to the Tenant Claims Gate's
# validate-deletions.sh). Removing an Environment claim hard-deletes the Environment (ArgoCD prune → Crossplane
# tears down the namespace; ECR is retained via deletionPolicy: Orphan). To make a one-shot destroy-of-active
# impossible, an Environment claim may only be deleted if it was first put into the `decommissioning` grace
# state (a separate, reversible PR — the Deprovision template). The deleted file still exists on the BASE
# checkout with its last committed phase, so we read it from there.
#
# Two guards:
#   1. Environment deletions are DECOMMISSION-FIRST — an Environment claim may only be deleted if it was already
#      put into the `decommissioning` grace state on base (Products carry no lifecycle, so this is env-only).
#   2. Product deletions are COMPLETENESS-checked — a Product may only be removed once it has NO remaining
#      Environments. "Remaining" = Environments present on base under gitops/environments/<team>/<product>/ that
#      this PR does not also delete (so one PR may tear down a Product together with its already-decommissioned
#      Environments, but cannot strand live ones). Deleting a Product with live Environments would orphan its
#      per-Product OIDC role / ECR repos / ApplicationSet and break the survivors' Composition render (their
#      Product join 404s). Both deletion classes are additionally admin-approval-gated by the gate commit status.
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
  # -r (raw scalar) so the compare is version-robust — older yq quotes the `// "active"` result; matches the
  # yq -r already used in validate-environments.sh.
  phase="$(yq -r '.spec.lifecycle.phase // "active"' "$base")"
  [ "$phase" = "decommissioning" ] || fail "${f}: cannot delete an active Environment. Set spec.lifecycle.phase: decommissioning first (the Deprovision template, or a claim edit), let that merge and the grace window pass, THEN remove the claim — guaranteeing a reversible window (ADR-062 #283)."
  echo "   ${f}: decommissioning on base — delete permitted"
  guarded=$((guarded + 1))
done

# ---- Guard 2: Product-deletion completeness (no remaining Environments) ----
# Build the set of Environment claims this PR deletes, so a same-PR Product+Environments teardown is allowed.
deleted_envs=" "
for f in $DELETED_FILES; do
  case "$f" in gitops/environments/*) deleted_envs="${deleted_envs}${f} ";; esac
done

prod_guarded=0
for f in $DELETED_FILES; do
  case "$f" in
    gitops/products/*) ;;
    *) continue ;;
  esac
  # gitops/products/<team>/<product>.yaml → team = parent dir, product = filename stem.
  p_team="$(basename "$(dirname "$f")")"
  p_prod="$(basename "$f")"; p_prod="${p_prod%.yaml}"; p_prod="${p_prod%.yml}"
  env_dir="${BASE_DIR}/gitops/environments/${p_team}/${p_prod}"
  remaining=""
  if [ -d "$env_dir" ]; then
    for ef in "$env_dir"/*.yaml "$env_dir"/*.yml; do
      [ -e "$ef" ] || continue
      rel="gitops/environments/${p_team}/${p_prod}/$(basename "$ef")"
      # An Environment also deleted by THIS PR doesn't count as remaining.
      case "$deleted_envs" in *" $rel "*) continue;; esac
      remaining="${remaining} ${rel#gitops/environments/${p_team}/${p_prod}/}"
    done
  fi
  [ -z "$remaining" ] || fail "${f}: cannot delete Product '${p_team}/${p_prod}' while Environments remain:${remaining}. Decommission and remove every Environment first (each is decommission-first guarded), THEN remove the Product — deleting it now would orphan its per-Product OIDC role / ECR / ApplicationSet and break the survivors' Composition render."
  echo "   ${f}: no remaining Environments for ${p_team}/${p_prod} — Product delete permitted"
  prod_guarded=$((prod_guarded + 1))
done

echo "v3-gate: ${guarded} Environment deletion(s) decommission-first; ${prod_guarded} Product deletion(s) completeness-checked"
