#!/usr/bin/env bash
# Unit test for validate-roles.sh — the WorkforceRole catalog gate (schema + enums + projection shape + the
# deletion guard / blast radius). Self-contained base/head fixtures; asserts exit codes (ok = 0, deny = != 0).
# Run locally: bash .github/scripts/roles-gate/test-validate-roles.sh   (needs mikefarah yq)
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="${here}/validate-roles.sh"
command -v yq >/dev/null 2>&1 || { echo "::error::yq required"; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
base="${work}/base"; head="${work}/head"
mkdir -p "${base}/gitops/people" "${head}/gitops/roles"

# A base roster: one Person grant references 'developer' (so a developer-deletion is blocked; blast radius = 1).
cat >"${base}/gitops/people/p.yaml" <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: Person
metadata: { name: p }
spec: { person: p, grants: [{ role: developer, team: alpha }] }
Y

role() { local rel="gitops/roles/$1.yaml"; mkdir -p "${head}/$(dirname "$rel")"; cat >"${head}/${rel}"; }

pass=0; fail=0
run() { # <expect> <label> <ROLE_FILES> [ROLE_DELETED_FILES]
  local expect="$1" label="$2" files="$3" del="${4:-}"
  BASE_DIR="$base" HEAD_DIR="$head" ROLE_FILES="$files" ROLE_DELETED_FILES="$del" \
    REPORT_MD="${work}/r.md" bash "$script" >/dev/null 2>&1
  local rc=$?
  if { [ "$expect" = ok ] && [ "$rc" -eq 0 ]; } || { [ "$expect" = deny ] && [ "$rc" -ne 0 ]; }; then
    pass=$((pass + 1)); echo "ok   - ${label} (rc ${rc})"
  else
    fail=$((fail + 1)); echo "FAIL - ${label} (expect ${expect}, rc ${rc})"
  fi
}

role developer <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: WorkforceRole
metadata: { name: developer }
spec:
  reach: team
  power: change
  mode: standing
  riskTier: standard
  description: dev
  identityCenter: { perTeam: true, permissionSet: "Dev-{team}", sessionDuration: PT4H, managedPolicies: ["arn:aws:iam::aws:policy/ReadOnlyAccess"] }
  keycloak: { realmRole: developer, perTeamGroup: true }
Y
run ok "valid full role" gitops/roles/developer.yaml

role minimal <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: WorkforceRole
metadata: { name: minimal }
spec: { reach: platform, power: look, mode: standing, riskTier: standard, description: minimal no-projection }
Y
run ok "valid minimal (no projections)" gitops/roles/minimal.yaml

role bad-kind <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: Role
metadata: { name: bad-kind }
spec: { reach: team, power: look, mode: standing, riskTier: standard, description: x }
Y
run deny "bad kind" gitops/roles/bad-kind.yaml

role mismatch <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: WorkforceRole
metadata: { name: other }
spec: { reach: team, power: look, mode: standing, riskTier: standard, description: x }
Y
run deny "metadata.name != filename" gitops/roles/mismatch.yaml

role bad-reach <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: WorkforceRole
metadata: { name: bad-reach }
spec: { reach: galaxy, power: look, mode: standing, riskTier: standard, description: x }
Y
run deny "bad reach enum" gitops/roles/bad-reach.yaml

role bad-power <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: WorkforceRole
metadata: { name: bad-power }
spec: { reach: team, power: superuser, mode: standing, riskTier: standard, description: x }
Y
run deny "bad power enum" gitops/roles/bad-power.yaml

role bad-mode <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: WorkforceRole
metadata: { name: bad-mode }
spec: { reach: team, power: look, mode: forever, riskTier: standard, description: x }
Y
run deny "bad mode enum" gitops/roles/bad-mode.yaml

role bad-risk <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: WorkforceRole
metadata: { name: bad-risk }
spec: { reach: team, power: look, mode: standing, riskTier: nuclear, description: x }
Y
run deny "bad riskTier enum" gitops/roles/bad-risk.yaml

role no-desc <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: WorkforceRole
metadata: { name: no-desc }
spec: { reach: team, power: look, mode: standing, riskTier: standard }
Y
run deny "missing description" gitops/roles/no-desc.yaml

role unknown-key <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: WorkforceRole
metadata: { name: unknown-key }
spec: { reach: team, power: look, mode: standing, riskTier: standard, description: x, color: blue }
Y
run deny "unknown spec key" gitops/roles/unknown-key.yaml

role ic-no-ps <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: WorkforceRole
metadata: { name: ic-no-ps }
spec: { reach: platform, power: look, mode: standing, riskTier: standard, description: x, identityCenter: { sessionDuration: PT4H } }
Y
run deny "identityCenter missing permissionSet" gitops/roles/ic-no-ps.yaml

role ic-bad-dur <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: WorkforceRole
metadata: { name: ic-bad-dur }
spec: { reach: platform, power: look, mode: standing, riskTier: standard, description: x, identityCenter: { permissionSet: ReadOnlyAccess, sessionDuration: 4hours } }
Y
run deny "identityCenter bad sessionDuration" gitops/roles/ic-bad-dur.yaml

role ic-unknown <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: WorkforceRole
metadata: { name: ic-unknown }
spec: { reach: platform, power: look, mode: standing, riskTier: standard, description: x, identityCenter: { permissionSet: ReadOnlyAccess, region: us-east-1 } }
Y
run deny "identityCenter unknown key" gitops/roles/ic-unknown.yaml

role kc-no-role <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: WorkforceRole
metadata: { name: kc-no-role }
spec: { reach: platform, power: look, mode: standing, riskTier: standard, description: x, keycloak: { perTeamGroup: false } }
Y
run deny "keycloak missing realmRole" gitops/roles/kc-no-role.yaml

# --- deletion guard / blast radius ------------------------------------------------------------------
run deny "delete a role still referenced by a Person grant" "" gitops/roles/developer.yaml
run ok  "delete an unreferenced role" "" gitops/roles/unused.yaml

echo "----"
echo "passed=${pass} failed=${fail}"
[ "$fail" -eq 0 ]
