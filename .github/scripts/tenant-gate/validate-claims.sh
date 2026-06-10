#!/usr/bin/env bash
# Tenant Claims Gate — per-claim validation (ADR-062 §3.1–3.3 + the §4 IAM lockout).
#
# Everything EXECUTABLE or AUTHORITATIVE (the XRD, the Composition, the tenant-policies chart, the Team
# CRs, this script) is read from the BASE checkout; only the claim YAMLs are read from the untrusted HEAD
# checkout, as data. Teams are deliberately never read from HEAD: a PR that adds a team and a claim for it
# in one shot must fail here (the privilege grant goes through the human-reviewed New Team flow).
#
# Env in:
#   BASE_DIR, HEAD_DIR      the two checkouts
#   CLAIM_FILES             space-separated added/modified claim paths (relative)
#   CLAIM_FILES_ADDED       subset of CLAIM_FILES with status=added (filename convention enforced)
#   BOT_AUTHOR              "true" when the PR author is the scaffolder write App
#   RENDER_CHECK            "false" to skip the docker-based composition render (local runs)
# Requires: yq, helm, kyverno, crossplane (crank), docker (when RENDER_CHECK).
set -euo pipefail

: "${BASE_DIR:?}" "${HEAD_DIR:?}"
CLAIM_FILES="${CLAIM_FILES:-}"
CLAIM_FILES_ADDED="${CLAIM_FILES_ADDED:-}"
BOT_AUTHOR="${BOT_AUTHOR:-false}"
RENDER_CHECK="${RENDER_CHECK:-true}"

XRD="${BASE_DIR}/infra/modules/crossplane/charts/tenant/templates/xrd.yaml"
COMPOSITION="${BASE_DIR}/infra/modules/crossplane/charts/tenant/files/composition-v2.yaml"
POLICY_CHART="${BASE_DIR}/infra/modules/crossplane/charts/tenant-policies"
RENDER_FIXTURES="${BASE_DIR}/infra/modules/crossplane/.tenant-api-tests/render"
NORMALIZE="${BASE_DIR}/.github/scripts/tenant-gate/normalize-claim.sh"
TEAMS_DIR="${BASE_DIR}/gitops/teams"

NAME_RE='^[a-z][a-z0-9]{1,15}$'
ENV_RE='^(dev|test|uat|staging|prod)$'

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fail() { echo "::error::tenant-gate: $*" >&2; exit 1; }

# Render the envelope policy once (Enforce — the dry-run must DENY, not audit).
ENVPOL="${work}/tenant-envelope.yaml"
helm template ktp "$POLICY_CHART" --show-only templates/tenant-envelope.yaml \
  --set envelopeFailureAction=Enforce >"$ENVPOL"
grep -q 'name: restrict-tenant-envelope' "$ENVPOL" || fail "envelope policy did not render from BASE chart"

for claim in $CLAIM_FILES; do
  f="${HEAD_DIR}/${claim}"
  echo "== validating ${claim} =="

  # --- shape / data-hygiene (the file is untrusted PR content) -------------------------------------
  [ -f "$f" ] || fail "${claim}: missing from head checkout"
  [ ! -L "$f" ] || fail "${claim}: symlinks are not allowed"
  [ "$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f")" -le 65536 ] || fail "${claim}: exceeds 64KB"
  [ "$(yq eval-all 'documentIndex' "$f" | tail -1)" = "0" ] || fail "${claim}: multi-document YAML is not allowed"

  kind="$(yq '.kind' "$f")"
  apiv="$(yq '.apiVersion' "$f")"
  [ "$kind" = "XTenant" ] || fail "${claim}: kind must be XTenant (got '${kind}')"
  [ "$apiv" = "platform.refplat.org/v1alpha2" ] || fail "${claim}: apiVersion must be platform.refplat.org/v1alpha2"

  team="$(yq '.spec.team' "$f")"
  name="$(yq '.spec.name' "$f")"
  environment="$(yq '.spec.environment' "$f")"
  metaname="$(yq '.metadata.name' "$f")"
  [[ "$team" =~ $NAME_RE ]] || fail "${claim}: spec.team '${team}' must match ${NAME_RE}"
  [[ "$name" =~ $NAME_RE ]] || fail "${claim}: spec.name '${name}' must match ${NAME_RE}"
  [[ "$environment" =~ $ENV_RE ]] || fail "${claim}: spec.environment '${environment}' invalid"
  expected="${team}-${name}-${environment}"
  [ "$metaname" = "$expected" ] || fail "${claim}: metadata.name '${metaname}' must be '${expected}'"
  [ "${#expected}" -le 63 ] || fail "${claim}: '${expected}' exceeds the 63-char namespace bound"
  if [[ " ${CLAIM_FILES_ADDED} " == *" ${claim} "* ]]; then
    [ "$(basename "$claim")" = "${expected}.yaml" ] || fail "${claim}: new claim files must be named <team>-<name>-<env>.yaml"
  fi

  # --- team must exist in BASE ----------------------------------------------------------------------
  team_yaml="${TEAMS_DIR}/${team}.yaml"
  [ -f "$team_yaml" ] || fail "${claim}: Team '${team}' does not exist on the base branch (gitops/teams/) — onboard the team first (New Team flow)"

  # --- IAM lockout (until #282) ---------------------------------------------------------------------
  iam="$(yq '[.spec.apps[]? | select(.permissions.aws.policyStatements != null)] | length' "$f")"
  [ "$iam" = "0" ] || fail "${claim}: spec.apps.*.permissions.aws.policyStatements is locked until the IAM-safety gate ships (#282) — remove it"

  # --- requester attribution (scaffolder-authored PRs, ADR-062 §4) ----------------------------------
  if [ "$BOT_AUTHOR" = "true" ]; then
    requester="$(yq '.metadata.annotations["platform.refplat.org/requested-by"] // ""' "$f")"
    [ -n "$requester" ] || fail "${claim}: scaffolder-authored claims must carry the platform.refplat.org/requested-by annotation"
  fi

  # --- schema (raw claim vs BASE XRD) ----------------------------------------------------------------
  crossplane beta validate "$XRD" "$f" || fail "${claim}: XRD schema validation failed"

  # --- envelope dry-run (normalized claim vs BASE Team CR, Kyverno offline) --------------------------
  normalized="${work}/$(basename "$claim").normalized.yaml"
  "$NORMALIZE" "$f" "$XRD" >"$normalized"
  values="${work}/values-${team}.yaml"
  yq '{"apiVersion": "cli.kyverno.io/v1alpha1", "kind": "Values",
       "metadata": {"name": "values"},
       "globalValues": {"team": {"metadata": {"name": .metadata.name},
                                  "spec": {"envelope": .spec.envelope}}}}' "$team_yaml" >"$values"
  out="$(kyverno apply "$ENVPOL" --resource "$normalized" --values-file "$values" 2>&1 || true)"
  if grep -q " failed" <<<"$out"; then
    printf '%s\n' "$out" >&2
    fail "${claim}: envelope dry-run DENIED (restrict-tenant-envelope) — claim exceeds Team '${team}' envelope"
  fi
  grep -Eq 'pass: [1-9]' <<<"$out" || { printf '%s\n' "$out" >&2; fail "${claim}: envelope dry-run evaluated no rules (vacuous pass) — gate bug or policy drift"; }

  # --- composition render (proves the Composition can build this claim) ------------------------------
  if [ "$RENDER_CHECK" = "true" ]; then
    rout="$(crossplane render "$f" "$COMPOSITION" "${RENDER_FIXTURES}/functions.yaml" \
      --extra-resources "${RENDER_FIXTURES}/environmentconfig.yaml" 2>&1)" ||
      { printf '%s\n' "$rout" >&2; fail "${claim}: composition render failed"; }
    grep -q 'kind:' <<<"$rout" || fail "${claim}: composition render produced no output"
  fi

  echo "   ${claim}: OK"
done

echo "tenant-gate: all claim validations passed"
