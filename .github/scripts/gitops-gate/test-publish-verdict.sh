#!/usr/bin/env bash
# Unit test for publish-verdict.sh (#501 release-approver + #283 deletion + #377 prod gate). Self-contained:
# builds a throwaway BASE registry (teams/products/environments) and runs the verdict in VERDICT_DRY_RUN with
# stubbed approvers/permissions, asserting exit code (0=success, 1=blocked). Run:
#   bash .github/scripts/gitops-gate/test-publish-verdict.sh
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="${here}/publish-verdict.sh"
command -v yq >/dev/null 2>&1 || { echo "::error::mikefarah yq required"; exit 1; }

base="$(mktemp -d)"
trap 'rm -rf "$base"' EXIT
mkdir -p "$base/gitops/teams" "$base/gitops/products/alpha" "$base/gitops/environments/alpha/reg"

# Team alpha: default approvers alice+bob. Team noapprover: no roles (fail-closed source).
cat >"$base/gitops/teams/alpha.yaml" <<'Y'
kind: Team
spec: { ssoGroup: Dev-alpha, roles: { releaseApprover: [alice, bob] } }
Y
cat >"$base/gitops/teams/noapprover.yaml" <<'Y'
kind: Team
spec: { ssoGroup: Dev-x }
Y
# Product alpha/shop OVERRIDES the team default to [carol]. alpha/reg + alpha/web have no override (team default).
cat >"$base/gitops/products/alpha/shop.yaml" <<'Y'
kind: Product
spec: { team: alpha, repo: o/r, roles: { releaseApprover: [carol] } }
Y
# A pci prod environment → requires 2 distinct approvers.
cat >"$base/gitops/environments/alpha/reg/prod.yaml" <<'Y'
kind: XEnvironment
spec: { team: alpha, product: reg, stage: prod, tier: pci }
Y

pass=0; failc=0
run() { # <expect ok|deny> <name> <VAR=VAL ...>
  local expect="$1" name="$2"; shift 2
  env REPO=o/r PR_NUMBER=1 HEAD_SHA=deadbeef000 STATUS_CONTEXT=Test BASE_DIR="$base" RUN_URL=- VERDICT_DRY_RUN=1 \
    "$@" bash "$script" >/tmp/_verdict_out 2>&1
  local rc=$? got=ok; [ $rc -ne 0 ] && got=deny
  if [ "$got" = "$expect" ]; then echo "  ok   $name"; pass=$((pass + 1))
  else echo "  FAIL $name (want $expect, got $got):"; sed 's/^/      /' /tmp/_verdict_out; failc=$((failc + 1)); fi
}

P=gitops/releases/alpha
run ok   "prod: team approver, != author"                 PROD_RELEASES=$P/web/prod.yaml AUTHOR=dev VERDICT_TEST_APPROVERS="alice"
run deny "prod: only the author approved"                 PROD_RELEASES=$P/web/prod.yaml AUTHOR=alice VERDICT_TEST_APPROVERS="alice"
run deny "prod: approver not in the set"                  PROD_RELEASES=$P/web/prod.yaml AUTHOR=dev VERDICT_TEST_APPROVERS="mallory"
run deny "prod: fail-closed (no approver configured)"     PROD_RELEASES=gitops/releases/noapprover/x/prod.yaml AUTHOR=dev VERDICT_TEST_APPROVERS="alice"
run ok   "prod: Product override (carol) accepted"        PROD_RELEASES=$P/shop/prod.yaml AUTHOR=dev VERDICT_TEST_APPROVERS="carol"
run deny "prod: team default rejected when override set"   PROD_RELEASES=$P/shop/prod.yaml AUTHOR=dev VERDICT_TEST_APPROVERS="alice"
run deny "prod: pci tier needs 2 (have 1)"                PROD_RELEASES=$P/reg/prod.yaml AUTHOR=dev VERDICT_TEST_APPROVERS="alice"
run ok   "prod: pci tier needs 2 (have 2)"                PROD_RELEASES=$P/reg/prod.yaml AUTHOR=dev VERDICT_TEST_APPROVERS="alice bob"
run deny "prod: pci 2 but one is the author"              PROD_RELEASES=$P/reg/prod.yaml AUTHOR=bob VERDICT_TEST_APPROVERS="alice bob"
run ok   "deletion: admin approver"                       DELETIONS=true AUTHOR=dev VERDICT_TEST_APPROVERS="alice" VERDICT_TEST_PERMS="alice=admin"
run deny "deletion: write-only approver"                  DELETIONS=true AUTHOR=dev VERDICT_TEST_APPROVERS="alice" VERDICT_TEST_PERMS="alice=write"
run ok   "roles-change (product): admin approver"         PRODUCT_ROLES_CHANGES=true AUTHOR=dev VERDICT_TEST_APPROVERS="alice" VERDICT_TEST_PERMS="alice=admin"
run deny "roles-change (team): no admin approval"         TEAM_ROLES_CHANGES=true AUTHOR=dev VERDICT_TEST_APPROVERS="alice" VERDICT_TEST_PERMS="alice=write"
run ok   "no reasons → success"                           AUTHOR=dev VERDICT_TEST_APPROVERS=""

echo "publish-verdict: ${pass} passed, ${failc} failed"
[ "$failc" -eq 0 ]
