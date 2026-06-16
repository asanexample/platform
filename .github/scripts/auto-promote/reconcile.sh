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
#   GH_TOKEN        asanexample-promote[bot] installation token (opens the Release PR on the platform repo)
#   PLATFORM_REPO   owner/name of the control-plane repo (default asanexample/platform)
#   KCTX            kubectl context for the platform cluster's ArgoCD (default: current context)
#   DRY_RUN         "true" → log what WOULD be promoted, open no PRs
# Requires: yq (mikefarah), kubectl (ArgoCD read), gh, git. Run from the repo root of a fresh platform checkout.
set -euo pipefail

REPO="${PLATFORM_REPO:-asanexample/platform}"
DRY_RUN="${DRY_RUN:-false}"

# kubectl against the platform cluster's ArgoCD, honouring an optional explicit context (default: current).
kc() {
  if [ -n "${KCTX:-}" ]; then kubectl --context "$KCTX" "$@"; else kubectl "$@"; fi
}

# The auto ladder — ADJACENT pairs (dev→test, test→uat, uat→staging). prod is NOT here (gated, Phase 3).
LADDER=(dev test uat staging)

git config user.name "asanexample-promote[bot]"
git config user.email "asanexample-promote[bot]@users.noreply.github.com"

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
      if [ -n "$(gh pr list --repo "$REPO" --head "$branch" --state open --json number --jq '.[0].number // empty' 2>/dev/null)" ]; then
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
      git push -q -u origin "$branch"
      gh pr create --repo "$REPO" --base main --head "$branch" \
        --title "promote: ${env_name} ${svc} -> ${short:0:12} (auto ${lower}→${upper})" \
        --body "Auto-promotion (#377 Phase 2): \`${lower}\` is Synced+Healthy on \`${lower_digest}\`, advancing the same signed digest to \`${upper}\`. The gitops Gate validates + auto-merges; the per-Product ApplicationSet injects it. The app repo's main is untouched."
      git checkout -q main
      git branch -q -D "$branch" 2>/dev/null || true
      echo "PROMOTE ${team}/${product} ${svc} ${lower}→${upper} @ ${lower_digest}"
      promoted=$((promoted + 1))
    done < <(yq -r '.spec.services | keys | .[]' "$lower_rel" 2>/dev/null)
  done
done

echo "auto-promote: ${promoted} promotion PR(s) opened, ${skipped} rung(s) waiting on lower-stage health."
