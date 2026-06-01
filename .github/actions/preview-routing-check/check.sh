#!/usr/bin/env bash
#
# Regression guard for platform issue #155 (ADR-032). PR preview environments apply a kustomize
# `namePrefix` (pr-<N>-) to isolate preview resources from the stable deployment. Gateway API
# HTTPRoute is a CRD not in kustomize's built-in nameReference list, so without the app's
# name-reference.yaml config a prefixed preview HTTPRoute keeps pointing at the un-prefixed (stable)
# Service. This renders the overlay the way ArgoCD does and fails if any HTTPRoute backendRef is not
# rewritten to the prefixed Service.
#
# Inputs (env): MANIFESTS_PATH (default k8s/preprod), PREFIX (default pr-citest-, must end with '-').
set -euo pipefail

: "${MANIFESTS_PATH:=k8s/preprod}"
: "${PREFIX:=pr-citest-}"

if [ ! -f "${MANIFESTS_PATH}/kustomization.yaml" ]; then
  echo "::error::${MANIFESTS_PATH}/kustomization.yaml not found — preview-enabled apps need a kustomize dir."
  exit 1
fi

work="$(mktemp -d)"
cp "${MANIFESTS_PATH}"/*.yaml "$work/"
# Simulate ArgoCD's PR-preview transform: prepend a namePrefix to the app's own kustomization, then
# build. This exercises the app's name-reference.yaml (referenced via `configurations:`) if present.
{ printf 'namePrefix: %s\n' "${PREFIX}"; cat "${MANIFESTS_PATH}/kustomization.yaml"; } > "$work/kustomization.yaml"

kubectl kustomize "$work" > "$work/rendered.yaml"

# PyYAML is preinstalled on GitHub-hosted ubuntu runners; install as a fallback for other images.
python3 -c "import yaml" 2>/dev/null || pip3 install --quiet pyyaml

python3 - "$work/rendered.yaml" "${PREFIX}" <<'PY'
import sys, yaml

rendered, prefix = sys.argv[1], sys.argv[2]
docs = [d for d in yaml.safe_load_all(open(rendered)) if d]

bad, seen = [], 0
for d in docs:
    if d.get("kind") != "HTTPRoute":
        continue
    for rule in (d.get("spec", {}).get("rules") or []):
        for ref in (rule.get("backendRefs") or []):
            seen += 1
            name = ref.get("name", "")
            if not name.startswith(prefix):
                bad.append((d["metadata"]["name"], name))

if bad:
    print("::error::HTTPRoute backendRef(s) not rewritten under namePrefix — is name-reference.yaml "
          "present and wired via kustomization.yaml's `configurations:`? (platform #155 / ADR-032)")
    for route, ref in bad:
        print(f"  route {route}: backendRef -> {ref!r} (expected the {prefix!r} prefix)")
    sys.exit(1)

if seen == 0:
    print(f"::warning::no HTTPRoute backendRefs found under {prefix!r} — nothing to check")
else:
    print(f"OK: {seen} HTTPRoute backendRef(s) correctly carry the {prefix!r} preview prefix")
PY
