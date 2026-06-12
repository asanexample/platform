#!/usr/bin/env bash
# v3 gitops gate (#388) — diff classification. Reads the PR's changed files from the GitHub API and splits
# them into the two v3 registry surfaces (the Product registry and the Environment claims). Classify-first:
# the gate job short-circuits to trivially-green when neither surface is touched, so it can be a REQUIRED
# check on every PR without blocking unrelated changes (and without rejecting v2, which is a different gate).
#
# Env in:  REPO (owner/name), PR_NUMBER, GH_TOKEN
# Out:     $GITHUB_OUTPUT (or stdout when unset) — keys:
#            product_files      space-separated added/modified gitops/products/**/*.yaml
#            environment_files  space-separated added/modified gitops/environments/**/*.yaml
#            deletions          "true" if any v3 registry file was removed or renamed-away
#            deleted_files      space-separated registry paths removed/renamed-away (read from BASE for the
#                               decommission-first guard); environments and products both included
#            non_v3_changes     "true" if the PR touches ANY file outside gitops/{products,environments} —
#                               used to gate auto-merge (a self-service PR must be v3-registry-only)
#            any                "true" if either surface has files to validate
set -euo pipefail
: "${REPO:?}" "${PR_NUMBER:?}"

PRODUCT_RE='^gitops/products/[a-z0-9-]+/[a-z0-9.-]+\.ya?ml$'
ENVIRON_RE='^gitops/environments/[a-z0-9-]+/[a-z0-9-]+/[a-z0-9.-]+\.ya?ml$'

files_json="$(gh api "repos/${REPO}/pulls/${PR_NUMBER}/files" --paginate --jq '[.[] | {filename, status, previous_filename}]')"

product_files=()
environment_files=()
deleted_files=()
deletions=false
non_v3_changes=false

add() { case "$1" in product) product_files+=("$2");; environment) environment_files+=("$2");; esac; }
match() { [[ "$1" =~ $PRODUCT_RE ]] && { echo product; return; }; [[ "$1" =~ $ENVIRON_RE ]] && { echo environment; return; }; echo ""; }

while IFS=$'\t' read -r filename status previous; do
  kind="$(match "$filename")"
  pkind="$(match "$previous")"
  case "$status" in
    added | modified | changed)
      if [ -n "$kind" ]; then add "$kind" "$filename"; else non_v3_changes=true; fi
      ;;
    removed)
      if [ -n "$kind" ]; then deletions=true; deleted_files+=("$filename"); else non_v3_changes=true; fi
      ;;
    renamed)
      # the new path: a v3 file is validated; a non-v3 destination is a non-v3 change
      if [ -n "$kind" ]; then add "$kind" "$filename"; else non_v3_changes=true; fi
      # the old path: a rename out of (or within) a registry surface drops it (a deletion of that path)
      if [ -n "$pkind" ]; then deletions=true; deleted_files+=("$previous"); fi
      ;;
  esac
done < <(jq -r '.[] | [.filename, .status, (.previous_filename // "")] | @tsv' <<<"$files_json")

any=false
{ [ ${#product_files[@]} -gt 0 ] || [ ${#environment_files[@]} -gt 0 ]; } && any=true

out="${GITHUB_OUTPUT:-/dev/stdout}"
{
  echo "product_files=${product_files[*]:-}"
  echo "environment_files=${environment_files[*]:-}"
  echo "deletions=${deletions}"
  echo "deleted_files=${deleted_files[*]:-}"
  echo "non_v3_changes=${non_v3_changes}"
  echo "any=${any}"
} >>"$out"
