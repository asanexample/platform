#!/usr/bin/env bash
#
# Create-or-update a sticky PR comment identified by a hidden marker. Uses the REST API via curl + jq so it
# runs on the self-hosted runner (no `gh` needed). The marker is the first line of the body (plan.sh emits it).
#
# Env: GITHUB_TOKEN, GITHUB_REPOSITORY (owner/repo), PR_NUMBER, MARKER, BODY_FILE.
set -euo pipefail
: "${GITHUB_TOKEN:?}" "${GITHUB_REPOSITORY:?}" "${PR_NUMBER:?}" "${MARKER:?}" "${BODY_FILE:?}"

api="https://api.github.com/repos/${GITHUB_REPOSITORY}"
auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}" -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28")

# JSON-encode the markdown body into a {"body": "..."} payload.
payload="$(jq -Rs '{body: .}' < "$BODY_FILE")"

# Find an existing sticky comment (one carrying the marker), if any.
existing="$(curl -fsSL "${auth[@]}" "${api}/issues/${PR_NUMBER}/comments?per_page=100" \
  | jq -r --arg m "$MARKER" 'map(select(.body | contains($m))) | .[0].id // empty')"

if [ -n "$existing" ]; then
  curl -fsSL -X PATCH "${auth[@]}" "${api}/issues/comments/${existing}" -d "$payload" > /dev/null
  echo "updated sticky comment ${existing}"
else
  curl -fsSL -X POST "${auth[@]}" "${api}/issues/${PR_NUMBER}/comments" -d "$payload" > /dev/null
  echo "created sticky comment"
fi
