#!/usr/bin/env bash
# Teams Gate — diff classification. Reads the PR's changed files from the GitHub API and splits the
# gitops/teams/ surface into added/modified vs removed/renamed-away. Anything outside gitops/teams/*.yaml
# is flagged (the gate validates only Team CRs; mixing other changes in is a review smell, not auto-blocked).
#
# Env in:  REPO (owner/name), PR_NUMBER, GH_TOKEN
# Out:     $GITHUB_OUTPUT (or stdout) — keys:
#            team_files          space-separated added/modified team paths
#            team_deleted_files  space-separated removed (or renamed-away) team paths
#            non_team_changes    "true" if the diff touches anything outside gitops/teams/*.yaml
set -euo pipefail

: "${REPO:?}" "${PR_NUMBER:?}"

TEAM_PATH_RE='^gitops/teams/[a-z0-9-]+\.ya?ml$'

files_json="$(gh api "repos/${REPO}/pulls/${PR_NUMBER}/files" --paginate --jq '[.[] | {filename, status, previous_filename}]')"

team_files=()
team_deleted_files=()
non_team_changes=false

while IFS=$'\t' read -r filename status previous; do
  # A README or other non-CR file under gitops/teams/ is not a Team CR — treat as a non-team change.
  if [[ "$filename" =~ $TEAM_PATH_RE && "$(basename "$filename")" != "README.yaml" ]]; then
    case "$status" in
      added | modified | changed) team_files+=("$filename") ;;
      removed) team_deleted_files+=("$filename") ;;
      renamed)
        # the old path disappears (treat as a deletion of that team); the new path is validated as added
        [ -n "$previous" ] && team_deleted_files+=("$previous")
        team_files+=("$filename")
        ;;
      *) non_team_changes=true ;;
    esac
  else
    non_team_changes=true
  fi
done < <(jq -r '.[] | [.filename, .status, (.previous_filename // "")] | @tsv' <<<"$files_json")

has_teams=false
{ [ "${#team_files[@]}" -gt 0 ] || [ "${#team_deleted_files[@]}" -gt 0 ]; } && has_teams=true

out="${GITHUB_OUTPUT:-/dev/stdout}"
{
  echo "team_files=${team_files[*]:-}"
  echo "team_deleted_files=${team_deleted_files[*]:-}"
  echo "non_team_changes=${non_team_changes}"
  echo "has_teams=${has_teams}" # gates the validation steps — the workflow runs on every PR (required-check
  #                               compatible) but only validates + comments when teams actually changed.
} >>"$out"
