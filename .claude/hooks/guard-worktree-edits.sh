#!/usr/bin/env bash
# PreToolUse hook (Edit|Write|MultiEdit): block edits to the main checkout — house rule is to make
# ALL changes in a worktree (isolation prevents accidental commits to the shared checkout; see
# CLAUDE.md -> Git Workflow). Detects "main checkout vs. linked worktree" via git's own convention:
# a linked worktree's git-dir is always <common-dir>/worktrees/<name>. PreToolUse exit 2 blocks the
# tool and feeds stderr back to Claude as the reason.
set -uo pipefail

input="$(cat)"
f="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')"
[ -z "$f" ] && exit 0

d="$(dirname "$f")"
gd="$(git -C "$d" rev-parse --absolute-git-dir 2>/dev/null)" || exit 0  # not a git repo — not our concern

case "$gd" in
  */.git/worktrees/*) exit 0 ;;  # already in a linked worktree — allowed
esac

echo "Blocked: editing directly in the main checkout. House rule is to make ALL changes in a worktree (EnterWorktree first, then retry this edit) — isolation prevents accidental commits to the shared checkout. See CLAUDE.md -> Git Workflow." >&2
exit 2
