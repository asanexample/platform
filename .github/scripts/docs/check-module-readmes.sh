#!/usr/bin/env bash
# Doc-currency gate: every leaf module under infra/modules/ must have a README.md.
#
# A "leaf module" is any directory containing *.tf files. New modules without a README fail the
# build. Pre-existing modules without a README are tolerated only while listed in
# known-missing-readmes.txt (the ratchet) — that list only shrinks as the correction pass adds the
# missing READMEs. This is the deterministic backstop for the audit's most unambiguous finding
# (modules shipped with no README, invisible to every doc inventory).
#
# Usage: .github/scripts/docs/check-module-readmes.sh
# Exit:  0 = ok, 1 = a module without a README that is NOT in the baseline (or a stale baseline entry).
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
BASELINE=".github/scripts/docs/known-missing-readmes.txt"

# Read the baseline allow-list (strip comments/blanks).
declare -A ALLOWED=()
if [ -f "$BASELINE" ]; then
  while IFS= read -r line; do
    line="${line%%#*}"; line="$(echo "$line" | xargs || true)"
    [ -n "$line" ] && ALLOWED["$line"]=1
  done < "$BASELINE"
fi

# All leaf modules = directories that directly contain *.tf files.
mapfile -t MODULES < <(git ls-files 'infra/modules/**/*.tf' | xargs -n1 dirname | sort -u)

missing=()       # leaf modules with no README, not baselined -> hard fail
stale_baseline=() # baselined paths that now HAVE a README (or no longer exist) -> remove from baseline
for m in "${MODULES[@]}"; do
  if [ ! -f "$m/README.md" ]; then
    if [ -n "${ALLOWED[$m]:-}" ]; then
      :  # tolerated by baseline
    else
      missing+=("$m")
    fi
  fi
done

# A baseline entry is stale if the module now has a README or the dir is gone.
for m in "${!ALLOWED[@]}"; do
  if [ -f "$m/README.md" ] || [ ! -d "$m" ]; then
    stale_baseline+=("$m")
  fi
done

rc=0
if [ "${#missing[@]}" -gt 0 ]; then
  echo "❌ doc-currency: these modules have no README.md (add one, or — only for genuine pre-existing debt — add to $BASELINE):"
  printf '   - %s\n' "${missing[@]}"
  rc=1
fi
if [ "${#stale_baseline[@]}" -gt 0 ]; then
  echo "❌ doc-currency: these $BASELINE entries are stale (module now has a README or was removed) — delete them from the baseline:"
  printf '   - %s\n' "${stale_baseline[@]}"
  rc=1
fi

if [ "$rc" -eq 0 ]; then
  echo "✅ doc-currency: all ${#MODULES[@]} leaf modules have a README (baseline allows ${#ALLOWED[@]})."
fi
exit "$rc"
