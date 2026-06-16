#!/usr/bin/env bash
# Watch a merged-or-closed Product PR and, once it MERGES, dispatch the registry-reconcile workflow (so a merged
# Product registry change is projected onto the cluster without waiting for the cron backstop). Polls ~15 min then
# gives up with a warning — the registry-reconcile cron is the safety net.
#
# Env in: GH_TOKEN, REPO (owner/name), PR_NUMBER.
# Requires: gh. Idempotent: a CLOSED-unmerged PR or a timeout both exit 0 (the cron handles the rest).
set -euo pipefail

: "${REPO:?}" "${PR_NUMBER:?}"

echo "Watching Product PR #$PR_NUMBER for auto-merge..."
for _ in $(seq 1 60); do # ~15 min — covers CI + the auto-merge; the registry-reconcile cron is the backstop
  state=$(gh pr view "$PR_NUMBER" --repo "$REPO" --json state --jq '.state')
  case "$state" in
  MERGED)
    echo "Product PR merged — dispatching registry-reconcile (workflow_dispatch is GITHUB_TOKEN-allowed)"
    gh workflow run registry-reconcile.yml --repo "$REPO"
    exit 0
    ;;
  CLOSED)
    echo "PR closed without merging — nothing to reconcile"
    exit 0
    ;;
  esac
  sleep 15
done
echo "::warning::PR #$PR_NUMBER not merged within ~15 min — the registry-reconcile cron will catch it"
