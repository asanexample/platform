#!/usr/bin/env bash
# People Gate — diff classification. Reads the PR's changed files from the GitHub API and splits the
# gitops/people/ surface into added/modified vs removed/renamed-away. Anything outside gitops/people/*.yaml
# is flagged (the gate validates only Person CRs; a README or other non-CR file is treated as a non-people
# change). Mirrors classify-teams.sh.
#
# Env in:  REPO (owner/name), PR_NUMBER, GH_TOKEN
# Out:     $GITHUB_OUTPUT (or stdout) — keys:
#            people_files          space-separated added/modified Person paths
#            people_deleted_files  space-separated removed (or renamed-away) Person paths
#            non_people_changes    "true" if the diff touches anything outside gitops/people/*.yaml
#            has_people            "true" if any Person CR was added/modified/removed
set -euo pipefail

: "${REPO:?}" "${PR_NUMBER:?}"

PERSON_PATH_RE='^gitops/people/[a-z0-9-]+\.ya?ml$'

files_json="$(gh api "repos/${REPO}/pulls/${PR_NUMBER}/files" --paginate --jq '[.[] | {filename, status, previous_filename}]')"

people_files=()
people_deleted_files=()
non_people_changes=false

while IFS=$'\t' read -r filename status previous; do
  # A README or other non-CR file under gitops/people/ is not a Person CR — treat as a non-people change.
  if [[ "$filename" =~ $PERSON_PATH_RE && "$(basename "$filename")" != "README.yaml" ]]; then
    case "$status" in
      added | modified | changed) people_files+=("$filename") ;;
      removed) people_deleted_files+=("$filename") ;;
      renamed)
        # the old path disappears (treat as a deletion of that person); the new path is validated as added
        [ -n "$previous" ] && people_deleted_files+=("$previous")
        people_files+=("$filename")
        ;;
      *) non_people_changes=true ;;
    esac
  else
    non_people_changes=true
  fi
done < <(jq -r '.[] | [.filename, .status, (.previous_filename // "")] | @tsv' <<<"$files_json")

has_people=false
{ [ "${#people_files[@]}" -gt 0 ] || [ "${#people_deleted_files[@]}" -gt 0 ]; } && has_people=true

out="${GITHUB_OUTPUT:-/dev/stdout}"
{
  echo "people_files=${people_files[*]:-}"
  echo "people_deleted_files=${people_deleted_files[*]:-}"
  echo "non_people_changes=${non_people_changes}"
  echo "has_people=${has_people}" # gates the validation steps — the workflow runs on every PR (required-check
  #                                 compatible) but only validates + comments when people actually changed.
} >>"$out"
