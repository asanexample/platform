#!/usr/bin/env bash
#
# Plan the access-model units (#305 Phase 1) and emit a markdown summary for the PR comment. Runs on the
# in-VPC `platform-infra` ARC runner, where terragrunt can reach the private EKS API + assume PlatformDeployer
# (force-assumed via TG_FORCE_DEPLOYER) and TerraformStateAccess. Per-unit plans are collapsed and truncated.
#
# Env: BASE (the platform unit parent dir), UNITS (space-separated), PLAN_MD (output file), RUN_URL (link).
# Exit: 0 if every unit planned, 1 if any failed (the comment still renders the failure).
set -uo pipefail

: "${BASE:?}" "${UNITS:?}" "${PLAN_MD:?}"
MAX_LINES="${MAX_LINES:-250}"

overall_rc=0
{
  echo "<!-- teams-plan -->"
  echo "## Teams plan — access-model units"
  echo
  echo "_\`terragrunt plan\` of the access-model units against this PR's \`gitops/teams\`, run on the in-VPC"
  echo "\`platform-infra\` runner. Review before merge; merging applies it (#305)._"
  echo
} > "$PLAN_MD"

for unit in $UNITS; do
  raw="$(mktemp)"
  if (cd "$BASE/$unit" && terragrunt plan -no-color -input=false) > "$raw" 2>&1; then
    status="planned"
  else
    status="PLAN FAILED"
    overall_rc=1
  fi
  lines=$(wc -l < "$raw")
  {
    echo "<details><summary><code>${unit}</code> — ${status}</summary>"
    echo
    echo '```text'
    if [ "$lines" -gt "$MAX_LINES" ]; then
      echo "... (truncated to the last ${MAX_LINES} of ${lines} lines — full output in the Actions run) ..."
      tail -n "$MAX_LINES" "$raw"
    else
      cat "$raw"
    fi
    echo '```'
    echo "</details>"
    echo
  } >> "$PLAN_MD"
  rm -f "$raw"
done

{
  echo "---"
  echo "_Updated by [\`teams-plan\`](${RUN_URL:-#}) on each push._"
} >> "$PLAN_MD"

exit "$overall_rc"
