#!/usr/bin/env bash
# Unit test for validate-people.sh — the Person-registry gate (schema + role catalog + team refs + anchor
# uniqueness). Self-contained: builds throwaway BASE_DIR (Team list + an existing Person) + HEAD_DIR (Person
# files) fixtures, runs the script with various PEOPLE_FILES, and asserts the exit code (ok = rc 0, deny = rc != 0).
# Run locally: bash .github/scripts/people-gate/test-validate-people.sh   (needs mikefarah yq)
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="${here}/validate-people.sh"
command -v yq >/dev/null 2>&1 || { echo "::error::yq required"; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
base="${work}/base"
head="${work}/head"

# Trusted base: team alpha exists; team ghost does NOT. An existing Person occupies anchor 'taken'.
mkdir -p "${base}/gitops/teams" "${base}/gitops/people"
cat >"${base}/gitops/teams/alpha.yaml" <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: Team
metadata: { name: alpha }
spec: { ssoGroup: Dev-alpha }
Y
cat >"${base}/gitops/people/existing.yaml" <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: Person
metadata: { name: existing }
spec: { person: taken, grants: [{ role: developer, team: alpha }] }
Y

person() { # <name> <yaml-body>  → writes gitops/people/<name>.yaml under head
  local rel="gitops/people/$1.yaml"; mkdir -p "${head}/$(dirname "$rel")"; cat >"${head}/${rel}"
}

pass=0; fail=0
run() { # <expect ok|deny> <label> <PEOPLE_FILES...>
  local expect="$1"; shift; local label="$1"; shift
  BASE_DIR="$base" HEAD_DIR="$head" PEOPLE_FILES="$*" PEOPLE_DELETED_FILES="" \
    REPORT_MD="${work}/report.md" bash "$script" >/dev/null 2>&1
  local rc=$?
  if { [ "$expect" = ok ] && [ "$rc" -eq 0 ]; } || { [ "$expect" = deny ] && [ "$rc" -ne 0 ]; }; then
    pass=$((pass + 1)); echo "ok   - ${label} (expect ${expect}, rc ${rc})"
  else
    fail=$((fail + 1)); echo "FAIL - ${label} (expect ${expect}, rc ${rc})"
  fi
}

# --- valid ------------------------------------------------------------------------------------------
person valid-team <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: Person
metadata: { name: valid-team }
spec: { person: dev-alpha, grants: [{ role: developer, team: alpha }] }
Y
run ok "valid team grant" gitops/people/valid-team.yaml

person valid-platform <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: Person
metadata: { name: valid-platform }
spec:
  person: admin
  handles: { github: gangster }
  grants:
    - { role: platform-admin, scope: platform }
    - { role: platform-operator, scope: platform, activation: on-demand }
Y
run ok "valid platform + on-demand + handle" gitops/people/valid-platform.yaml

# --- schema / identity ------------------------------------------------------------------------------
person bad-kind <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: Widget
metadata: { name: bad-kind }
spec: { person: x, grants: [{ role: developer, team: alpha }] }
Y
run deny "bad kind" gitops/people/bad-kind.yaml

person name-mismatch <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: Person
metadata: { name: someone-else }
spec: { person: x, grants: [{ role: developer, team: alpha }] }
Y
run deny "metadata.name != filename" gitops/people/name-mismatch.yaml

person no-anchor <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: Person
metadata: { name: no-anchor }
spec: { grants: [{ role: developer, team: alpha }] }
Y
run deny "missing spec.person" gitops/people/no-anchor.yaml

person email-anchor <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: Person
metadata: { name: email-anchor }
spec: { person: someone@example.com, grants: [{ role: developer, team: alpha }] }
Y
run deny "email as anchor (PII)" gitops/people/email-anchor.yaml

person unknown-key <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: Person
metadata: { name: unknown-key }
spec: { person: x, email: nope, grants: [{ role: developer, team: alpha }] }
Y
run deny "unknown spec key" gitops/people/unknown-key.yaml

person bad-handle <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: Person
metadata: { name: bad-handle }
spec: { person: x, handles: { github: "not a login!" }, grants: [{ role: developer, team: alpha }] }
Y
run deny "invalid github handle" gitops/people/bad-handle.yaml

# --- grants -----------------------------------------------------------------------------------------
person empty-grants <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: Person
metadata: { name: empty-grants }
spec: { person: x, grants: [] }
Y
run deny "empty grants" gitops/people/empty-grants.yaml

person both-reach <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: Person
metadata: { name: both-reach }
spec: { person: x, grants: [{ role: developer, team: alpha, scope: platform }] }
Y
run deny "grant with both team and scope" gitops/people/both-reach.yaml

person no-reach <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: Person
metadata: { name: no-reach }
spec: { person: x, grants: [{ role: developer }] }
Y
run deny "grant with neither team nor scope" gitops/people/no-reach.yaml

person ghost-team <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: Person
metadata: { name: ghost-team }
spec: { person: x, grants: [{ role: developer, team: ghost }] }
Y
run deny "team grant to nonexistent team" gitops/people/ghost-team.yaml

person bad-team-role <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: Person
metadata: { name: bad-team-role }
spec: { person: x, grants: [{ role: platform-admin, team: alpha }] }
Y
run deny "platform role on a team grant" gitops/people/bad-team-role.yaml

person bad-plat-role <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: Person
metadata: { name: bad-plat-role }
spec: { person: x, grants: [{ role: developer, scope: platform }] }
Y
run deny "team role on a platform grant" gitops/people/bad-plat-role.yaml

person bad-scope <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: Person
metadata: { name: bad-scope }
spec: { person: x, grants: [{ role: viewer, scope: galaxy }] }
Y
run deny "invalid scope" gitops/people/bad-scope.yaml

person bad-activation <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: Person
metadata: { name: bad-activation }
spec: { person: x, grants: [{ role: developer, team: alpha, activation: always }] }
Y
run deny "invalid activation" gitops/people/bad-activation.yaml

person grant-unknown-key <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: Person
metadata: { name: grant-unknown-key }
spec: { person: x, grants: [{ role: developer, team: alpha, until: friday }] }
Y
run deny "unknown grant key" gitops/people/grant-unknown-key.yaml

# --- anchor uniqueness ------------------------------------------------------------------------------
person collide-base <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: Person
metadata: { name: collide-base }
spec: { person: taken, grants: [{ role: developer, team: alpha }] }
Y
run deny "anchor collides with an existing base Person" gitops/people/collide-base.yaml

person dupe-a <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: Person
metadata: { name: dupe-a }
spec: { person: shared-anchor, grants: [{ role: developer, team: alpha }] }
Y
person dupe-b <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: Person
metadata: { name: dupe-b }
spec: { person: shared-anchor, grants: [{ role: developer, team: alpha }] }
Y
run deny "two PR Persons share one anchor" gitops/people/dupe-a.yaml gitops/people/dupe-b.yaml

echo "----"
echo "passed=${pass} failed=${fail}"
[ "$fail" -eq 0 ]
