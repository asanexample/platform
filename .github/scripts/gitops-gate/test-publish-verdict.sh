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
mkdir -p "$base/gitops/teams" "$base/gitops/products/alpha" "$base/gitops/people" \
  "$base/gitops/environments/alpha/reg" "$base/gitops/environments/alpha/web"

# Teams just exist (ssoGroup); approver-holding is now a Person grant (ADR-090), NOT Team.roles.
cat >"$base/gitops/teams/alpha.yaml" <<'Y'
kind: Team
spec: { ssoGroup: Dev-alpha }
Y
cat >"$base/gitops/teams/noapprover.yaml" <<'Y'
kind: Team
spec: { ssoGroup: Dev-x }
Y
# Products carry no approver override anymore (retired with the per-product reach — ADR-090 D3).
cat >"$base/gitops/products/alpha/shop.yaml" <<'Y'
kind: Product
spec: { team: alpha, repo: o/r }
Y
# The release-approver set for team alpha is DERIVED from these Person grants → {alice, bob}. alice's handle is
# mixed-case (proves case-insensitive matching); bob also holds developer (proves the role filter); carol holds
# only developer (proves a non-holder is excluded — and that the retired per-product 'carol' override is gone).
cat >"$base/gitops/people/alice.yaml" <<'Y'
kind: Person
spec: { person: alice, handles: { github: Alice }, grants: [ { role: release-approver, team: alpha } ] }
Y
cat >"$base/gitops/people/bob.yaml" <<'Y'
kind: Person
spec: { person: bob, handles: { github: bob }, grants: [ { role: developer, team: alpha }, { role: release-approver, team: alpha } ] }
Y
cat >"$base/gitops/people/carol.yaml" <<'Y'
kind: Person
spec: { person: carol, handles: { github: carol }, grants: [ { role: developer, team: alpha } ] }
Y
# A pci prod environment → requires 2 distinct approvers.
cat >"$base/gitops/environments/alpha/reg/prod.yaml" <<'Y'
kind: XEnvironment
spec: { team: alpha, product: reg, stage: prod, tier: pci }
Y
# Prod-env teardown fixtures (Deprovision Product purge): a standard prod env + a dev env under alpha/web.
cat >"$base/gitops/environments/alpha/web/prod.yaml" <<'Y'
kind: XEnvironment
spec: { team: alpha, product: web, stage: prod, tier: standard }
Y
cat >"$base/gitops/environments/alpha/web/dev.yaml" <<'Y'
kind: XEnvironment
spec: { team: alpha, product: web, stage: dev, tier: standard }
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
run ok   "prod: shop uses team-derived set (alice)"        PROD_RELEASES=$P/shop/prod.yaml AUTHOR=dev VERDICT_TEST_APPROVERS="alice"
run deny "prod: shop rejects carol (per-product override retired)" PROD_RELEASES=$P/shop/prod.yaml AUTHOR=dev VERDICT_TEST_APPROVERS="carol"
run deny "prod: pci tier needs 2 (have 1)"                PROD_RELEASES=$P/reg/prod.yaml AUTHOR=dev VERDICT_TEST_APPROVERS="alice"
run ok   "prod: pci tier needs 2 (have 2)"                PROD_RELEASES=$P/reg/prod.yaml AUTHOR=dev VERDICT_TEST_APPROVERS="alice bob"
run deny "prod: pci 2 but one is the author"              PROD_RELEASES=$P/reg/prod.yaml AUTHOR=bob VERDICT_TEST_APPROVERS="alice bob"
run ok   "deletion: admin approver"                       DELETIONS=true AUTHOR=dev VERDICT_TEST_APPROVERS="alice" VERDICT_TEST_PERMS="alice=admin"
run deny "deletion: write-only approver"                  DELETIONS=true AUTHOR=dev VERDICT_TEST_APPROVERS="alice" VERDICT_TEST_PERMS="alice=write"
# Prod-env teardown (Deprovision Product purge) — needs the release-approver ON TOP OF the generic admin deletion.
E=gitops/environments/alpha
run ok   "purge: prod env, admin+release-approver (alice)" DELETIONS=true DELETED_FILES=$E/web/prod.yaml AUTHOR=dev VERDICT_TEST_APPROVERS="alice" VERDICT_TEST_PERMS="alice=admin"
run deny "purge: prod env, admin but NOT release-approver" DELETIONS=true DELETED_FILES=$E/web/prod.yaml AUTHOR=dev VERDICT_TEST_APPROVERS="dave" VERDICT_TEST_PERMS="dave=admin"
run deny "purge: prod env pci needs 2 (have 1)"           DELETIONS=true DELETED_FILES=$E/reg/prod.yaml AUTHOR=dev VERDICT_TEST_APPROVERS="alice" VERDICT_TEST_PERMS="alice=admin"
run ok   "purge: prod env pci needs 2 (have 2)"           DELETIONS=true DELETED_FILES=$E/reg/prod.yaml AUTHOR=dev VERDICT_TEST_APPROVERS="alice bob" VERDICT_TEST_PERMS="alice=admin bob=admin"
run ok   "purge: NON-prod env → only generic admin"       DELETIONS=true DELETED_FILES=$E/web/dev.yaml AUTHOR=dev VERDICT_TEST_APPROVERS="dave" VERDICT_TEST_PERMS="dave=admin"
run ok   "purge: prod product file delete → no env gate"  DELETIONS=true DELETED_FILES=gitops/products/alpha/web.yaml AUTHOR=dev VERDICT_TEST_APPROVERS="dave" VERDICT_TEST_PERMS="dave=admin"
run ok   "roles-change (product): admin approver"         PRODUCT_ROLES_CHANGES=true AUTHOR=dev VERDICT_TEST_APPROVERS="alice" VERDICT_TEST_PERMS="alice=admin"
run deny "roles-change (team): no admin approval"         TEAM_ROLES_CHANGES=true AUTHOR=dev VERDICT_TEST_APPROVERS="alice" VERDICT_TEST_PERMS="alice=write"
# Environment decommission — ANY one approving review ≠ author (no permission tier).
run deny "decommission: no approval yet"                  LIFECYCLE_DECOMMISSION=true AUTHOR=scaffolderbot VERDICT_TEST_APPROVERS=""
run ok   "decommission: a human approved (no tier)"       LIFECYCLE_DECOMMISSION=true AUTHOR=scaffolderbot VERDICT_TEST_APPROVERS="gangster"
run deny "decommission: only the author approved"         LIFECYCLE_DECOMMISSION=true AUTHOR=gangster VERDICT_TEST_APPROVERS="gangster"
run ok   "decommission: write-level approver is fine"     LIFECYCLE_DECOMMISSION=true AUTHOR=bot VERDICT_TEST_APPROVERS="dev" VERDICT_TEST_PERMS="dev=write"
run ok   "no reasons → success"                           AUTHOR=dev VERDICT_TEST_APPROVERS=""

# Solo-maintainer escape (single-admin project): SOLO_MAINTAINER=true + an admin/maintainer AUTHOR self-attests
# every privileged surface (no separate approver needed — GitHub won't let you approve your own PR). A non-admin
# author is unaffected, and with the flag OFF an admin author still can't self-approve (the bug we're fixing).
run ok   "solo: admin author self-attests team-roles"     SOLO_MAINTAINER=true TEAM_ROLES_CHANGES=true AUTHOR=gangster VERDICT_TEST_PERMS="gangster=admin" VERDICT_TEST_APPROVERS=""
run ok   "solo: maintain author self-attests prod release" SOLO_MAINTAINER=true PROD_RELEASES=$P/web/prod.yaml AUTHOR=gangster VERDICT_TEST_PERMS="gangster=maintain" VERDICT_TEST_APPROVERS=""
run ok   "solo: admin author self-attests deletion"       SOLO_MAINTAINER=true DELETIONS=true AUTHOR=gangster VERDICT_TEST_PERMS="gangster=admin" VERDICT_TEST_APPROVERS=""
run ok   "solo: admin author self-attests prod-env purge" SOLO_MAINTAINER=true DELETIONS=true DELETED_FILES=$E/web/prod.yaml AUTHOR=gangster VERDICT_TEST_PERMS="gangster=admin" VERDICT_TEST_APPROVERS=""
run deny "solo: NON-admin author still needs approval"    SOLO_MAINTAINER=true TEAM_ROLES_CHANGES=true AUTHOR=dev VERDICT_TEST_PERMS="dev=write" VERDICT_TEST_APPROVERS=""
run deny "solo OFF: admin author can't self-approve (control)" TEAM_ROLES_CHANGES=true AUTHOR=gangster VERDICT_TEST_PERMS="gangster=admin" VERDICT_TEST_APPROVERS=""

echo "publish-verdict: ${pass} passed, ${failc} failed"
[ "$failc" -eq 0 ]
