#!/usr/bin/env bash
# Tenant Claims Gate — diff classification (ADR-062 §3.4, the path/diff restriction).
#
# Reads the PR's changed files from the GitHub API (no merge-ref checkout needed) and classifies them
# against the automergeable claim surface. v1 scope is gitops/tenant-claims/preprod/ ONLY — the single
# directory the tenant-claims ArgoCD app watches; a claim anywhere else would pass validation but sync
# nowhere, which is confusion masquerading as success. Widen when a second claims dir exists.
#
# Env in:  REPO (owner/name), PR_NUMBER, GH_TOKEN
# Out:     $GITHUB_OUTPUT (or stdout when unset) — keys:
#            claim_files        space-separated added/modified claim paths
#            claim_deletions    "true" if any claim file was removed or renamed
#            non_claim_changes  "true" if the diff touches anything outside the claim surface
set -euo pipefail

: "${REPO:?}" "${PR_NUMBER:?}"

CLAIM_PATH_RE='^gitops/tenant-claims/preprod/[a-z0-9.-]+\.ya?ml$'

files_json="$(gh api "repos/${REPO}/pulls/${PR_NUMBER}/files" --paginate --jq '[.[] | {filename, status, previous_filename}]')"

claim_files=()
claim_files_added=()
claim_deleted_files=()
claim_deletions=false
non_claim_changes=false

while IFS=$'\t' read -r filename status previous; do
  if [[ "$filename" =~ $CLAIM_PATH_RE ]]; then
    case "$status" in
      added)
        claim_files+=("$filename")
        claim_files_added+=("$filename")
        ;;
      modified | changed) claim_files+=("$filename") ;;
      removed)
        claim_deletions=true
        claim_deleted_files+=("$filename")
        ;;
      renamed)
        claim_deletions=true # the old path disappears; treat like a removal
        [ -n "$previous" ] && claim_deleted_files+=("$previous")
        claim_files+=("$filename")
        claim_files_added+=("$filename")
        ;;
      *) non_claim_changes=true ;;
    esac
  else
    non_claim_changes=true
  fi
  # A rename FROM a claim path to elsewhere also removes a claim.
  if [[ "$status" == "renamed" && -n "$previous" && "$previous" =~ $CLAIM_PATH_RE && ! "$filename" =~ $CLAIM_PATH_RE ]]; then
    claim_deletions=true
  fi
done < <(jq -r '.[] | [.filename, .status, (.previous_filename // "")] | @tsv' <<<"$files_json")

out="${GITHUB_OUTPUT:-/dev/stdout}"
{
  echo "claim_files=${claim_files[*]:-}"
  echo "claim_files_added=${claim_files_added[*]:-}"
  echo "claim_deleted_files=${claim_deleted_files[*]:-}"
  echo "claim_deletions=${claim_deletions}"
  echo "non_claim_changes=${non_claim_changes}"
} >>"$out"
