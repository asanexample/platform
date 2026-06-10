#!/usr/bin/env bash
# Tenant Claims Gate — claim normalization. Fills the XRD's schema defaults into a raw claim so the
# offline envelope dry-run and the aggregate-quota sum see what ADMISSION sees (the API server defaults
# the object before Kyverno evaluates it; `kyverno apply` offline does not). Defaults are extracted from
# the BASE xrd.yaml itself — never hard-coded — so schema changes can't drift the gate.
#
# Usage: normalize-claim.sh <claim.yaml> <xrd.yaml>   (normalized YAML on stdout)
set -euo pipefail

claim="${1:?claim file}"
xrd="${2:?xrd file}"

spec_props=".spec.versions[] | select(.name == \"v1alpha2\") | .schema.openAPIV3Schema.properties.spec.properties"

tier_default="$(yq "${spec_props}.tier.default" "$xrd")"
cpu_default="$(yq "${spec_props}.quota.properties.cpu.default" "$xrd")"
mem_default="$(yq "${spec_props}.quota.properties.memory.default" "$xrd")"
pods_default="$(yq "${spec_props}.quota.properties.pods.default" "$xrd")"

for v in tier_default cpu_default mem_default pods_default; do
  [ "${!v}" != "null" ] || { echo "::error::normalize-claim: could not extract ${v} from ${xrd}" >&2; exit 1; }
done

TIER="$tier_default" CPU="$cpu_default" MEM="$mem_default" PODS="$pods_default" yq '
  .spec.tier = (.spec.tier // strenv(TIER)) |
  .spec.quota.cpu = (.spec.quota.cpu // strenv(CPU)) |
  .spec.quota.memory = (.spec.quota.memory // strenv(MEM)) |
  .spec.quota.pods = (.spec.quota.pods // (env(PODS) | to_number)) |
  .spec.residency.allowedLocations = (.spec.residency.allowedLocations // ["*"])
' "$claim"
