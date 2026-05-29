#!/usr/bin/env bash
# Renders the platform policies chart and runs the Kyverno CLI test suite against it.
# Cluster-free: matches CI. Requires `helm` and `kyverno` (pin the CLI to the chart's appVersion).
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART="$DIR/../policies-chart"

mkdir -p "$DIR/rendered"
helm template kpp "$CHART" \
  --set validationFailureAction=Enforce \
  --set failurePolicy=Fail \
  --set complianceTier=standard \
  --set-json 'allowedRegistries=["829808296602.dkr.ecr.us-east-1.amazonaws.com"]' \
  --set-json 'tenantRegistryMap={"alpha":"829808296602.dkr.ecr.us-east-1.amazonaws.com/team-alpha"}' \
  >"$DIR/rendered/policies.yaml"

cd "$DIR"
kyverno test .
