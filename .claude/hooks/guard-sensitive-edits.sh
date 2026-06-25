#!/usr/bin/env bash
# PreToolUse hook (Edit|Write|MultiEdit): block direct edits to the SOPS-encrypted secrets file.
# Editing the ciphertext by hand corrupts it; the cleartext is edited via `sops`. PreToolUse
# exit 2 blocks the tool and feeds stderr back to Claude as the reason.
set -uo pipefail

input="$(cat)"
f="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')"

case "$f" in
  *infra/live/aws/secrets.enc.yaml)
    echo "Blocked: secrets.enc.yaml is SOPS-encrypted (ADR-066) — never edit the ciphertext directly (it corrupts the file). Edit the cleartext with 'sops infra/live/aws/secrets.enc.yaml' (KMS decrypt/re-encrypt round-trip), or use the gitignored plaintext path under TG_SOPS_BOOTSTRAP for a greenfield bootstrap. See CLAUDE.md -> Secrets." >&2
    exit 2
    ;;
esac
exit 0
