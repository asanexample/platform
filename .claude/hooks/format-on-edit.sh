#!/usr/bin/env bash
# PostToolUse hook (Edit|Write|MultiEdit): keep the file the agent just touched correct-by-
# construction, so we don't round-trip through CI for formatting/lint.
#
#   *.tf  under infra/  -> `tofu fmt`              (deterministic auto-format, silent)
#   *.hcl under infra/  -> `terragrunt hcl fmt`    (deterministic auto-format, silent)
#   *.md                -> `markdownlint-cli2 --fix` (auto-fix the mechanical, e.g. MD031;
#                          then surface anything unfixable, e.g. MD040, back to Claude so it
#                          fixes it THIS turn instead of at CI)
#
# PostToolUse can't block (the tool already ran); exit 2 just feeds stderr to Claude. We only
# do that for markdown lint findings. Formatting failures are swallowed (the agent may be
# mid-edit; validate/CI will still catch real syntax errors).
set -uo pipefail

input="$(cat)"
f="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')"
[ -n "$f" ] || exit 0

root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
# Resolve relative paths under the repo; ignore anything outside the project.
case "$f" in
  /*) ;;                                  # absolute
  *)  f="$root/$f" ;;                     # relative -> under repo root
esac
case "$f" in "$root"/*) ;; *) exit 0 ;; esac
[ -f "$f" ] || exit 0

case "$f" in
  *.tf)
    case "$f" in *"/infra/"*) tofu fmt "$f" >/dev/null 2>&1 || true ;; esac
    exit 0
    ;;
  *.hcl)
    case "$f" in *"/infra/"*) terragrunt hcl fmt --file "$f" >/dev/null 2>&1 || true ;; esac
    exit 0
    ;;
  *.md)
    # Run from repo root so the repo's .markdownlint.yml / .markdownlintignore apply (match CI).
    out="$(cd "$root" && npx -y markdownlint-cli2 --fix "$f" 2>&1)"
    rc=$?
    if [ "$rc" -ne 0 ]; then
      printf 'markdownlint flagged %s (auto-fixable issues were already fixed in place; the rest need a manual fix — e.g. MD040 needs a language on the fence):\n%s\n' "$f" "$out" >&2
      exit 2
    fi
    exit 0
    ;;
esac
exit 0
