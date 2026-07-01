#!/usr/bin/env bash
# PreToolUse hook (Edit|Write|MultiEdit): block edits to the main checkout of THIS repo (platform) — house
# rule is to make ALL changes in a worktree (isolation prevents accidental commits to the shared checkout;
# see CLAUDE.md -> Git Workflow). Detects "main checkout vs. linked worktree" via git's own convention: a
# linked worktree's git-dir is always <common-dir>/worktrees/<name>. Scoped to THIS SCRIPT's own repo only
# (derived from its own location, not $CLAUDE_PROJECT_DIR — not reliably set in the hook's runtime, and
# every worktree carries its own copy of this file at the same relative path, so "this script's repo"
# resolves correctly whether running from main or a worktree). Editing a file in some OTHER git repo (e.g.
# a scratch clone of an app repo for a test PR) has nothing to do with the crossplane orphan-sweep danger
# this rule exists for, and must not be blocked here. PreToolUse exit 2 blocks the tool and feeds stderr
# back to Claude as the reason.
set -uo pipefail

input="$(cat)"
f="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')"
[ -z "$f" ] && exit 0

d="$(dirname "$f")"
gd="$(git -C "$d" rev-parse --absolute-git-dir 2>/dev/null)" || exit 0  # not a git repo — not our concern

common_dir_of() {
  case "$1" in
    */.git/worktrees/*) echo "${1%%/worktrees/*}" ;;
    *) echo "$1" ;;
  esac
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
platform_gd="$(git -C "$script_dir" rev-parse --absolute-git-dir 2>/dev/null)" || exit 0
[ "$(common_dir_of "$gd")" != "$(common_dir_of "$platform_gd")" ] && exit 0  # a different repo entirely — not our concern

case "$gd" in
  */.git/worktrees/*) exit 0 ;;  # already in a linked worktree of the platform repo — allowed
esac

echo "Blocked: editing directly in the main checkout. House rule is to make ALL changes in a worktree (EnterWorktree first, then retry this edit) — isolation prevents accidental commits to the shared checkout. See CLAUDE.md -> Git Workflow." >&2
exit 2
