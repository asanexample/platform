#!/usr/bin/env bash
# Roles Gate — diff classification. Splits the gitops/roles/ surface into added/modified vs removed/renamed-away.
# Anything outside gitops/roles/*.yaml is flagged. Mirrors classify-people.sh / classify-teams.sh.
#
# Env in:  REPO (owner/name), PR_NUMBER, GH_TOKEN
# Out:     $GITHUB_OUTPUT (or stdout):
#            role_files          space-separated added/modified WorkforceRole paths
#            role_deleted_files  space-separated removed (or renamed-away) WorkforceRole paths
#            non_role_changes    "true" if the diff touches anything outside gitops/roles/*.yaml
#            has_roles           "true" if any WorkforceRole was added/modified/removed
set -euo pipefail

: "${REPO:?}" "${PR_NUMBER:?}"

ROLE_PATH_RE='^gitops/roles/[a-z0-9-]+\.ya?ml$'

files_json="$(gh api "repos/${REPO}/pulls/${PR_NUMBER}/files" --paginate --jq '[.[] | {filename, status, previous_filename}]')"

role_files=()
role_deleted_files=()
non_role_changes=false

while IFS=$'\t' read -r filename status previous; do
  if [[ "$filename" =~ $ROLE_PATH_RE && "$(basename "$filename")" != "README.yaml" ]]; then
    case "$status" in
      added | modified | changed) role_files+=("$filename") ;;
      removed) role_deleted_files+=("$filename") ;;
      renamed)
        [ -n "$previous" ] && role_deleted_files+=("$previous")
        role_files+=("$filename")
        ;;
      *) non_role_changes=true ;;
    esac
  else
    non_role_changes=true
  fi
done < <(jq -r '.[] | [.filename, .status, (.previous_filename // "")] | @tsv' <<<"$files_json")

has_roles=false
{ [ "${#role_files[@]}" -gt 0 ] || [ "${#role_deleted_files[@]}" -gt 0 ]; } && has_roles=true

out="${GITHUB_OUTPUT:-/dev/stdout}"
{
  echo "role_files=${role_files[*]:-}"
  echo "role_deleted_files=${role_deleted_files[*]:-}"
  echo "non_role_changes=${non_role_changes}"
  echo "has_roles=${has_roles}"
} >>"$out"
