#!/usr/bin/env bash
# Auto-promotion reconciler (#377 Phase 2 — auto ≤ staging). Walks each Product's stage ladder and advances the
# deployed digest UP one rung wherever the lower stage is live and the upper stage is behind — so the SAME signed
# artifact climbs dev → test → uat → staging with no operator action. prod is DELIBERATELY excluded: its promotion
# is gated (approver != author, #377 Phase 3). This is the automated sibling of the on-demand app-repo Promote
# workflow — both end in a `asanexample-promote[bot]` Release PR that the gitops Gate validates + auto-merges and
# the per-Product ApplicationSet injects.
#
# The promotion is gated per rung on the LOWER stage being a healthy, settled deployment of its current digest:
# its ArgoCD Application must be Synced + Healthy (the appset injects the Release digest, so Synced+Healthy ⇒ the
# lower digest is actually running). The digest therefore climbs ONE rung per run, baking at each stage until the
# next reconcile sees it healthy — a real ladder, not a fan-out.
#
# Idempotent + safe to run on a schedule: a rung already carrying the lower digest is skipped, and a promotion
# whose branch already has an open PR is not reopened. Pooled environments only (the <stage>.yaml files); per-
# customer environments (<customer>-<stage>.yaml) are a follow-up.
#
# Env in:
#   GH_TOKEN                    asanexample-promote[bot] installation token (opens the Release PR on the platform repo)
#   PLATFORM_REPO               owner/name of the control-plane repo (default asanexample/platform)
#   KCTX                        kubectl context for the platform cluster's ArgoCD (default: current context)
#   DRY_RUN                     "true" → log what WOULD be promoted, open no PRs
#   MERGE_WAIT_TIMEOUT_SECONDS  how long to poll for each promotion PR's gate merge before moving on
#                               (default 300 — see the wait loop below for why this exists)
# Requires: yq (mikefarah), kubectl (ArgoCD read), gh, git. Run from the repo root of a fresh platform checkout.
set -euo pipefail

REPO="${PLATFORM_REPO:-asanexample/platform}"
DRY_RUN="${DRY_RUN:-false}"

# kubectl against the platform cluster's ArgoCD, honouring an optional explicit context (default: current).
kc() {
  if [ -n "${KCTX:-}" ]; then kubectl --context "$KCTX" "$@"; else kubectl "$@"; fi
}

# GitHub REST API as the promote App — the platform-infra runner image has no `gh` CLI, but curl + jq are present.
api() { curl -fsS -H "Authorization: Bearer ${GH_TOKEN}" -H "Accept: application/vnd.github+json" "$@"; }

# The auto ladder — ADJACENT pairs (dev→test, test→uat, uat→staging). prod is NOT here (gated, Phase 3).
LADDER=(dev test uat staging)

git config user.name "asanexample-promote[bot]"
git config user.email "asanexample-promote[bot]@users.noreply.github.com"

# Push + open the Release PR AS the promote App — its token (GH_TOKEN) has contents+pull_requests write on the
# platform repo, and the gate only auto-merges asanexample-promote[bot] PRs. The workflow's checkout step sets
# persist-credentials: false specifically so nothing here fights the promote App's token; repoint origin at it
# regardless (belt-and-suspenders — cheap insurance if that setting is ever dropped from the workflow).
# (Skipped in DRY_RUN — and harmless where there is no origin, e.g. local tests.)
#
# Gotcha (found the hard way): a bare `git config --unset-all "http.https://github.com/.extraheader"` here does
# NOT undo actions/checkout's default credential — modern actions/checkout persists it via a temp config file
# wired in through `includeIf.gitdir`, not a plain key in this repo's own .git/config, so an --unset-all against
# the local config silently finds nothing to remove (its `|| true` masked that). The push then authenticates as
# github-actions[bot] instead of the promote App and fails with a 403 — with NO log line pointing at the cause,
# since it happens mid-loop on whatever service is first found promotable. persist-credentials: false on the
# checkout step is the actual fix (never sets up the conflicting credential in the first place); this unset
# stays only as a no-op safety net.
if [ "$DRY_RUN" != "true" ]; then
  git remote set-url origin "https://x-access-token:${GH_TOKEN}@github.com/${REPO}.git"
  git config --unset-all "http.https://github.com/.extraheader" 2>/dev/null || true
fi

# Read a service's digest from a Release file (empty if the file/service/digest is absent).
rel_digest() { # <release-file> <service>
  [ -f "$1" ] || { echo ""; return; }
  SVC="$2" yq -r '.spec.services[strenv(SVC)].digest // ""' "$1" 2>/dev/null || echo ""
}

promoted=0
skipped=0

shopt -s nullglob
for prod_file in gitops/products/*/*.yaml; do
  product="$(basename "$prod_file" .yaml)"
  team="$(basename "$(dirname "$prod_file")")"

  for ((i = 0; i < ${#LADDER[@]} - 1; i++)); do
    lower="${LADDER[i]}"
    upper="${LADDER[i + 1]}"
    lower_rel="gitops/releases/${team}/${product}/${lower}.yaml"
    upper_rel="gitops/releases/${team}/${product}/${upper}.yaml"
    upper_env="gitops/environments/${team}/${product}/${upper}.yaml"

    [ -f "$lower_rel" ] || continue # nothing deployed at the lower stage
    [ -f "$upper_env" ] || continue # no upper Environment → nowhere to promote yet

    # Each Service the lower stage currently has a digest for.
    while IFS= read -r svc; do
      [ -n "$svc" ] || continue
      lower_digest="$(rel_digest "$lower_rel" "$svc")"
      [ -n "$lower_digest" ] || continue

      [ "$(rel_digest "$upper_rel" "$svc")" = "$lower_digest" ] && continue # already promoted

      # The upper Environment must DECLARE the Service (the gate rejects a Release for an undeclared Service).
      [ "$(SVC="$svc" yq -r '.spec.services | has(strenv(SVC))' "$upper_env" 2>/dev/null)" = "true" ] || continue

      # Health gate: the lower stage's ArgoCD Application must be Synced + Healthy (settled on its digest).
      app="${team}-${product}-${lower}"
      sync="$(kc -n argocd get application "$app" -o jsonpath='{.status.sync.status}' 2>/dev/null || true)"
      health="$(kc -n argocd get application "$app" -o jsonpath='{.status.health.status}' 2>/dev/null || true)"
      if [ "$sync" != "Synced" ] || [ "$health" != "Healthy" ]; then
        echo "wait  ${team}/${product} ${svc} ${lower}→${upper}: lower not settled (sync=${sync:-?} health=${health:-?})"
        skipped=$((skipped + 1))
        continue
      fi

      env_name="${team}-${product}-${upper}"
      short="${lower_digest#sha256:}"
      branch="auto-promote/${env_name}-${svc}-${short}"

      if [ "$DRY_RUN" = "true" ]; then
        echo "WOULD promote ${team}/${product} ${svc} ${lower}→${upper} @ ${lower_digest}"
        promoted=$((promoted + 1))
        continue
      fi

      # Don't reopen a promotion already in flight (a prior run's PR not yet merged).
      if [ -n "$(api "https://api.github.com/repos/${REPO}/pulls?head=${REPO%%/*}:${branch}&state=open" 2>/dev/null | jq -r '.[0].number // empty' 2>/dev/null)" ]; then
        echo "open  ${team}/${product} ${svc} ${lower}→${upper}: PR already open for ${branch}"
        continue
      fi

      # Create-or-update the upper Release (same shape promote.yml writes), then open the promote-bot PR.
      mkdir -p "$(dirname "$upper_rel")"
      [ -f "$upper_rel" ] || echo '{}' >"$upper_rel"
      ENV_NAME="$env_name" SVC="$svc" DIGEST="$lower_digest" yq -i '
        .apiVersion = "platform.refplat.org/v1beta1" | .kind = "Release"
        | .metadata.name = strenv(ENV_NAME)
        | .spec.environmentRef = strenv(ENV_NAME)
        | .spec.services[strenv(SVC)].digest = strenv(DIGEST)
      ' "$upper_rel"

      git add "$upper_rel"
      if git diff --cached --quiet; then
        git reset -q
        continue
      fi

      git checkout -q -b "$branch"
      git commit -q -m "promote: ${env_name} ${svc} -> sha256:${short}"
      # Force-push (#1528 follow-up): the branch name is content-deterministic (env+svc+digest), so a same-name
      # branch already existing remotely can only be a leftover from an earlier attempt at promoting this EXACT
      # digest (e.g. a closed promote PR whose branch delete silently failed) — never a different, unrelated
      # change. Force is always safe here: this script is the sole writer of these branches (each pushed branch
      # is deleted immediately below), so there is nothing else to clobber.
      git push -q -f -u origin "$branch"
      pr_title="promote: ${env_name} ${svc} -> ${short:0:12} (auto ${lower}→${upper})"
      pr_body="Auto-promotion (#377 Phase 2): \`${lower}\` is Synced+Healthy on \`${lower_digest}\`, advancing the same signed digest to \`${upper}\`. The gitops Gate validates + auto-merges; the per-Product ApplicationSet injects it. The app repo's main is untouched."
      pr_number="$(api -X POST "https://api.github.com/repos/${REPO}/pulls" \
        -d "$(jq -n --arg t "$pr_title" --arg h "$branch" --arg b "$pr_body" '{title: $t, head: $h, base: "main", body: $b}')" | jq -r '.number')"
      git checkout -q main
      git branch -q -D "$branch" 2>/dev/null || true
      # Wait for the gate to actually MERGE this PR before branching the next promotion off main — not just
      # re-fetch-and-hope. A prior fix (re-fetch + ff-only merge here, no wait) helped but didn't close the
      # race: the gate's checks+approval automation reliably takes longer than this loop's ~10s per-service
      # cadence, so whenever two services in one run promote to the SAME upper_rel, every PR after the first
      # still branches from a main that doesn't yet include it and conflicts. Confirmed live, repeatedly
      # (#1516-1519, then again #1546-1550 and #1562-1565 on the SAME evening despite the re-fetch fix) —
      # only ever the first of N same-file promotions in a run merged cleanly. Polling for the real merge
      # (not just pushing and moving on) is the only way the NEXT branch-off is guaranteed to start from a
      # main that already contains this one. Bounded so one wedged PR (e.g. a genuine gate rejection) can't
      # hang the whole run — falls through to the next promotion, which the following run's open-PR check
      # will still catch and can retry.
      wait_deadline=$((SECONDS + ${MERGE_WAIT_TIMEOUT_SECONDS:-300}))
      merged=false
      while [ "$SECONDS" -lt "$wait_deadline" ]; do
        if [ "$(api "https://api.github.com/repos/${REPO}/pulls/${pr_number}" | jq -r '.merged // false')" = "true" ]; then
          merged=true
          break
        fi
        sleep 5
      done
      if [ "$merged" != "true" ]; then
        echo "::warning::PR #${pr_number} (${env_name} ${svc}) did not merge within ${MERGE_WAIT_TIMEOUT_SECONDS:-300}s — continuing without waiting further"
      fi
      git fetch -q origin main && git merge -q --ff-only origin/main || true
      echo "PROMOTE ${team}/${product} ${svc} ${lower}→${upper} @ ${lower_digest}"
      promoted=$((promoted + 1))
    done < <(yq -r '.spec.services | keys | .[]' "$lower_rel" 2>/dev/null)
  done
done

echo "auto-promote: ${promoted} promotion PR(s) opened, ${skipped} rung(s) waiting on lower-stage health."
