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
#            any                "true" if either surface has files to validate
set -euo pipefail
: "${REPO:?}" "${PR_NUMBER:?}"

PRODUCT_RE='^gitops/products/[a-z0-9-]+/[a-z0-9.-]+\.ya?ml$'
ENVIRON_RE='^gitops/environments/[a-z0-9-]+/[a-z0-9-]+/[a-z0-9.-]+\.ya?ml$'

files_json="$(gh api "repos/${REPO}/pulls/${PR_NUMBER}/files" --paginate --jq '[.[] | {filename, status, previous_filename}]')"

product_files=()
environment_files=()
deletions=false

add() { case "$1" in product) product_files+=("$2");; environment) environment_files+=("$2");; esac; }
match() { [[ "$1" =~ $PRODUCT_RE ]] && { echo product; return; }; [[ "$1" =~ $ENVIRON_RE ]] && { echo environment; return; }; echo ""; }

while IFS=$'\t' read -r filename status previous; do
  kind="$(match "$filename")"
  pkind="$(match "$previous")"
  case "$status" in
    added | modified | changed) [ -n "$kind" ] && add "$kind" "$filename" ;;
    removed) [ -n "$kind" ] && deletions=true ;;
    renamed)
      [ -n "$kind" ] && add "$kind" "$filename"
      # a rename out of (or within) a registry surface drops the old path
      [ -n "$pkind" ] && deletions=true
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
  echo "any=${any}"
} >>"$out"
