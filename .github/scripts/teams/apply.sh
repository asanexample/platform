#!/usr/bin/env bash
#
# Apply the access-model units on merge (#305 Phase 1). keycloak-config + argocd always apply; argocd-apps
# applies only if it has a diff (a no-op until the team has tenant claims). Fail-fast in dependency order
# (argocd reads keycloak-config's outputs; argocd-apps reads argocd's). Output -> the job summary.
#
# Env: BASE (the platform unit parent dir). GITHUB_STEP_SUMMARY is provided by Actions.
set -uo pipefail
: "${BASE:?}"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"

echo "## Teams apply — access-model units" >> "$SUMMARY"

run() {
  local unit="$1" mode="$2" raw rc status
  raw="$(mktemp)"
  echo "::group::terragrunt ${mode} — ${unit}"
  if [ "$mode" = conditional ]; then
    rc=0
    (cd "$BASE/$unit" && terragrunt plan -detailed-exitcode -no-color -input=false) > "$raw" 2>&1 || rc=$?
    case "$rc" in
      0) status="no changes — skipped" ;;
      2) if (cd "$BASE/$unit" && terragrunt apply -auto-approve -no-color -input=false) >> "$raw" 2>&1; then status="applied"; else status="APPLY FAILED"; fi ;;
      *) status="PLAN FAILED" ;;
    esac
  else
    if (cd "$BASE/$unit" && terragrunt apply -auto-approve -no-color -input=false) > "$raw" 2>&1; then status="applied"; else status="APPLY FAILED"; fi
  fi
  cat "$raw"
  echo "::endgroup::"
  {
    echo "<details><summary><code>${unit}</code> — ${status}</summary>"
    echo
    echo '```text'
    tail -n 200 "$raw"
    echo '```'
    echo "</details>"
    echo
  } >> "$SUMMARY"
  rm -f "$raw"
  case "$status" in *FAILED*) return 1 ;; esac
  return 0
}

run keycloak-config apply || { echo "::error::keycloak-config apply failed — stopping"; exit 1; }
run argocd apply || { echo "::error::argocd apply failed — stopping"; exit 1; }
run argocd-apps conditional || { echo "::error::argocd-apps failed — stopping"; exit 1; }
echo "access-model units converged"
