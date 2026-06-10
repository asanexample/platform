#!/usr/bin/env bash
# Tenant Claims Gate — aggregate-quota hard gate (ADR-062 §3.5).
#
# Admission can only check a single claim ≤ quotaCap (stateless); the team-AGGREGATE cap is report-first
# at runtime. CI is stateful — it can read every claim — so this makes the aggregate a BLOCKING check:
# for each team touched by the PR, sum the (XRD-defaulted) quotas of all of the team's claims in the
# PR-result tree and require sum ≤ Team.envelope.quotaCap, plus a global tenant-count ceiling.
#
# The PR-result tree = BASE claims overlaid with the PR's adds/modifies, minus its deletions — never the
# head tree alone (a stale branch must not hide claims that landed on base after it forked).
#
# Env in: BASE_DIR, HEAD_DIR, CLAIM_FILES, CLAIM_DELETED_FILES (optional), MAX_TENANTS_PER_TEAM (default 10)
set -euo pipefail

: "${BASE_DIR:?}" "${HEAD_DIR:?}"
CLAIM_FILES="${CLAIM_FILES:-}"
CLAIM_DELETED_FILES="${CLAIM_DELETED_FILES:-}"
MAX_TENANTS_PER_TEAM="${MAX_TENANTS_PER_TEAM:-10}"

XRD="${BASE_DIR}/infra/modules/crossplane/charts/tenant/templates/xrd.yaml"
NORMALIZE="${BASE_DIR}/.github/scripts/tenant-gate/normalize-claim.sh"
CLAIMS_REL="gitops/tenant-claims/preprod"

fail() { echo "::error::tenant-gate(aggregate): $*" >&2; exit 1; }

# cpu → millicores; memory → Mi
to_millicores() { case "$1" in *m) echo "${1%m}" ;; *) echo "$(($1 * 1000))" ;; esac; }
to_mi() {
  case "$1" in
  *Gi) echo "$((${1%Gi} * 1024))" ;;
  *Mi) echo "${1%Mi}" ;;
  *) fail "unsupported memory unit '$1' (use Mi/Gi)" ;;
  esac
}

merged="$(mktemp -d)"
trap 'rm -rf "$merged"' EXIT
mkdir -p "${merged}/${CLAIMS_REL}"
cp "${BASE_DIR}/${CLAIMS_REL}"/*.yaml "${merged}/${CLAIMS_REL}/" 2>/dev/null || true
for c in $CLAIM_FILES; do cp "${HEAD_DIR}/${c}" "${merged}/${c}"; done
for d in $CLAIM_DELETED_FILES; do rm -f "${merged}/${d}"; done

teams="$(for c in $CLAIM_FILES; do yq '.spec.team' "${HEAD_DIR}/${c}"; done | sort -u)"

for team in $teams; do
  team_yaml="${BASE_DIR}/gitops/teams/${team}.yaml"
  [ -f "$team_yaml" ] || fail "team '${team}' missing on base"
  cap_cpu="$(to_millicores "$(yq '.spec.envelope.quotaCap.cpu' "$team_yaml")")"
  cap_mem="$(to_mi "$(yq '.spec.envelope.quotaCap.memory' "$team_yaml")")"
  cap_pods="$(yq '.spec.envelope.quotaCap.pods' "$team_yaml")"

  sum_cpu=0 sum_mem=0 sum_pods=0 count=0
  for f in "${merged}/${CLAIMS_REL}"/*.yaml; do
    [ "$(yq '.spec.team' "$f")" = "$team" ] || continue
    count=$((count + 1))
    norm="$("$NORMALIZE" "$f" "$XRD")"
    sum_cpu=$((sum_cpu + $(to_millicores "$(yq '.spec.quota.cpu' - <<<"$norm")")))
    sum_mem=$((sum_mem + $(to_mi "$(yq '.spec.quota.memory' - <<<"$norm")")))
    sum_pods=$((sum_pods + $(yq '.spec.quota.pods' - <<<"$norm")))
  done

  echo "team ${team}: ${count} tenants, cpu ${sum_cpu}m/${cap_cpu}m, mem ${sum_mem}Mi/${cap_mem}Mi, pods ${sum_pods}/${cap_pods}"
  [ "$count" -le "$MAX_TENANTS_PER_TEAM" ] || fail "team '${team}' would have ${count} tenants (> ${MAX_TENANTS_PER_TEAM})"
  [ "$sum_cpu" -le "$cap_cpu" ] || fail "team '${team}' aggregate cpu ${sum_cpu}m exceeds quotaCap ${cap_cpu}m"
  [ "$sum_mem" -le "$cap_mem" ] || fail "team '${team}' aggregate memory ${sum_mem}Mi exceeds quotaCap ${cap_mem}Mi"
  [ "$sum_pods" -le "$cap_pods" ] || fail "team '${team}' aggregate pods ${sum_pods} exceeds quotaCap ${cap_pods}"
done

echo "tenant-gate: aggregate quota within envelope for: ${teams:-"(no teams)"}"
