#!/usr/bin/env bash
# wait-for-http.sh — poll a URL until it returns HTTP 2xx, or time out.
#
# Used as a Terragrunt before_hook to gate units that configure a service through
# its LIVE endpoint (e.g. keycloak-config -> Keycloak): apply only runs once the
# endpoint actually responds, so a from-scratch rebuild never needs
# `platctl bootstrap --resume` to ride out the cert/NLB/DNS/pod readiness lag
# (ADR-059). TLS is verified (no -k) so the gate also waits for the real
# Let's Encrypt cert — the same path the consuming provider will use.
#
# Usage: wait-for-http.sh <url> [timeout_seconds] [interval_seconds]
set -euo pipefail

url="${1:?usage: wait-for-http.sh <url> [timeout_seconds] [interval_seconds]}"
timeout="${2:-600}"
interval="${3:-10}"

deadline=$((SECONDS + timeout))
attempt=0

echo "wait-for-http: polling ${url} (timeout ${timeout}s, interval ${interval}s)"
while true; do
  attempt=$((attempt + 1))
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "${url}" 2>/dev/null || true)
  [ -z "${code}" ] && code="000"

  case "${code}" in
  2??)
    echo "wait-for-http: ready after ${attempt} attempt(s) (HTTP ${code})"
    exit 0
    ;;
  esac

  if [ "${SECONDS}" -ge "${deadline}" ]; then
    echo "wait-for-http: TIMEOUT after ${timeout}s waiting for ${url} (last HTTP ${code})" >&2
    echo "  hint: deployer on Tailscale? gateway cert issued + NLB/DNS ready? try: platctl validate --check gateway" >&2
    exit 1
  fi

  echo "  attempt ${attempt}: HTTP ${code}; retrying in ${interval}s…"
  sleep "${interval}"
done
