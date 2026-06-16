#!/usr/bin/env bash
# gitops gate (#388) — diff classification. Reads the PR's changed files from the GitHub API and splits
# them into the three registry surfaces (the Product registry, the Environment claims, and the Release
# digest records — ADR-071). Classify-first: the gate job short-circuits to trivially-green when no surface
# is touched, so it can be a REQUIRED check on every PR without blocking unrelated changes (and without
# rejecting v2, which is a different gate).
#
# Env in:  REPO (owner/name), PR_NUMBER, GH_TOKEN
# Out:     $GITHUB_OUTPUT (or stdout when unset) — keys:
#            product_files      space-separated added/modified gitops/products/**/*.yaml
#            environment_files  space-separated added/modified gitops/environments/**/*.yaml
#            release_files      space-separated added/modified gitops/releases/**/*.yaml (ADR-071 digest bumps)
#            prod_release_files space-separated added/modified releases targeting the PROD stage
#                               (<stem> = prod or <customer>-prod) — the gated-prod subset (#377 Phase 3)
#            deletions          "true" if any registry file was removed or renamed-away
#            deleted_files      space-separated registry paths removed/renamed-away (read from BASE for the
#                               decommission-first guard); environments and products both included
#            non_registry_changes     "true" if the PR touches ANY file outside gitops/{products,environments,releases} —
#                               used to gate auto-merge (a self-service PR must be registry-only)
#            any                "true" if any surface has files to validate
set -euo pipefail
: "${REPO:?}" "${PR_NUMBER:?}"

PRODUCT_RE='^gitops/products/[a-z0-9-]+/[a-z0-9.-]+\.ya?ml$'
ENVIRON_RE='^gitops/environments/[a-z0-9-]+/[a-z0-9-]+/[a-z0-9.-]+\.ya?ml$'
RELEASE_RE='^gitops/releases/[a-z0-9-]+/[a-z0-9-]+/[a-z0-9.-]+\.ya?ml$'
# A prod-stage release: stem is `prod` (pooled) or `<customer>-prod` (per-customer). The gated subset (#377 P3).
PROD_RELEASE_RE='^gitops/releases/[a-z0-9-]+/[a-z0-9-]+/(prod|[a-z0-9-]+-prod)\.ya?ml$'

files_json="$(gh api "repos/${REPO}/pulls/${PR_NUMBER}/files" --paginate --jq '[.[] | {filename, status, previous_filename}]')"

product_files=()
environment_files=()
release_files=()
prod_release_files=()
deleted_files=()
deletions=false
non_registry_changes=false

add() {
  case "$1" in
    product) product_files+=("$2") ;;
    environment) environment_files+=("$2") ;;
    release)
      release_files+=("$2")
      [[ "$2" =~ $PROD_RELEASE_RE ]] && prod_release_files+=("$2")
      ;;
  esac
}
match() { [[ "$1" =~ $PRODUCT_RE ]] && { echo product; return; }; [[ "$1" =~ $ENVIRON_RE ]] && { echo environment; return; }; [[ "$1" =~ $RELEASE_RE ]] && { echo release; return; }; echo ""; }

while IFS=$'\t' read -r filename status previous; do
  kind="$(match "$filename")"
  pkind="$(match "$previous")"
  case "$status" in
    added | modified | changed)
      if [ -n "$kind" ]; then add "$kind" "$filename"; else non_registry_changes=true; fi
      ;;
    removed)
      if [ -n "$kind" ]; then deletions=true; deleted_files+=("$filename"); else non_registry_changes=true; fi
      ;;
    renamed)
      # the new path: a file is validated; a non-destination is a non-change
      if [ -n "$kind" ]; then add "$kind" "$filename"; else non_registry_changes=true; fi
      # the old path: a rename out of (or within) a registry surface drops it (a deletion of that path)
      if [ -n "$pkind" ]; then deletions=true; deleted_files+=("$previous"); fi
      ;;
  esac
done < <(jq -r '.[] | [.filename, .status, (.previous_filename // "")] | @tsv' <<<"$files_json")

any=false
{ [ ${#product_files[@]} -gt 0 ] || [ ${#environment_files[@]} -gt 0 ] || [ ${#release_files[@]} -gt 0 ]; } && any=true

out="${GITHUB_OUTPUT:-/dev/stdout}"
{
  echo "product_files=${product_files[*]:-}"
  echo "environment_files=${environment_files[*]:-}"
  echo "release_files=${release_files[*]:-}"
  echo "prod_release_files=${prod_release_files[*]:-}"
  echo "deletions=${deletions}"
  echo "deleted_files=${deleted_files[*]:-}"
  echo "non_registry_changes=${non_registry_changes}"
  echo "any=${any}"
} >>"$out"
