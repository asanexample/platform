#!/usr/bin/env bash
# Doc-currency gate: a module's terraform-docs-generated README block must be up to date.
#
# Runs terraform-docs in --output-check mode (writes nothing) against each given module that has a
# terraform-docs-managed README (one containing the BEGIN_TF_DOCS markers). Hand-written READMEs
# (no markers) are skipped. This is the deterministic backstop for the audit's biggest mechanical
# class: "code changed, terraform-docs not re-run" (wrong defaults, phantom/omitted inputs).
#
# Usage:
#   check-terraform-docs.sh <module-dir> [<module-dir> ...]   # check specific modules (CI: changed only)
#   check-terraform-docs.sh                                     # full sweep of all marker READMEs
# Exit: 0 = all fresh/skipped, 1 = at least one stale (regenerate with the printed command).
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
CONFIG=".terraform-docs.yml"

if ! command -v terraform-docs > /dev/null 2>&1; then
  echo "❌ doc-currency: terraform-docs not installed (CI installs it; locally: brew install terraform-docs)"
  exit 1
fi

# Target list: args, or every leaf module if none given.
if [ "$#" -gt 0 ]; then
  TARGETS=("$@")
else
  mapfile -t TARGETS < <(git ls-files 'infra/modules/**/*.tf' | xargs -n1 dirname | sort -u)
fi

stale=() checked=0 skipped=0
for dir in "${TARGETS[@]}"; do
  dir="${dir%/}"
  # Only modules with a terraform-docs-managed README are in scope.
  if [ ! -f "$dir/README.md" ] || ! grep -q "BEGIN_TF_DOCS" "$dir/README.md"; then
    skipped=$((skipped + 1)); continue
  fi
  checked=$((checked + 1))
  # --output-check exits non-zero if the injected block is not current; it writes nothing.
  if ! terraform-docs --config "$CONFIG" --output-check "$dir" > /dev/null 2>&1; then
    stale+=("$dir")
  fi
done

if [ "${#stale[@]}" -gt 0 ]; then
  echo "❌ doc-currency: these modules' README terraform-docs blocks are stale — regenerate them:"
  for d in "${stale[@]}"; do echo "   - $d   →   terraform-docs --config $CONFIG $d"; done
  echo "   (a change to a module's variables/outputs/resources must regenerate its README.)"
  exit 1
fi
echo "✅ doc-currency: terraform-docs fresh ($checked checked, $skipped skipped as hand-written/no-README)."
exit 0
