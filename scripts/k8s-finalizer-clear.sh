#!/usr/bin/env bash
# k8s-finalizer-clear.sh — strip finalizers from named/typed k8s resources so they delete cleanly during
# teardown, with ROBUST cluster auth. Controllers that would otherwise process the finalizers are themselves
# being torn down, so their resources (tailscale Connector, Crossplane Provider/XRD/Composition, CNPG Cluster)
# would hang the helm uninstall / kubernetes delete. Run from a `when = destroy` provisioner BEFORE those deletes.
#
# It sets up its own throwaway kubeconfig (aws eks update-kubeconfig + the deployer role) — the bug this fixes was
# `kubectl patch ... || true` with no guaranteed context, which silently no-ops during teardown.
#
# BEST-EFFORT: never blocks destroy — always exits 0 (if the cluster is already gone, there's nothing to clear).
#
# Usage:
#   k8s-finalizer-clear.sh [--delete] <cluster> <region> <role_arn> <namespace|-> <ref...>
#     ref = "kind/name" (one resource) or "kind" (ALL of that kind, via --all)
#     namespace "-" = cluster-scoped
#     --delete = issue `kubectl delete ... --wait=false` BEFORE stripping finalizers. Use when nothing else
#                deletes the resource (e.g. a Crossplane CR the helm uninstall would otherwise hang on): delete
#                sets deletionTimestamp, then the finalizer strip forces removal regardless of the controller.
#                Omit when terraform/helm already issues the delete and you only need the finalizer gone first.
set -uo pipefail

do_delete=0
if [ "${1:-}" = "--delete" ]; then do_delete=1; shift; fi

cluster="${1:?usage: k8s-finalizer-clear.sh [--delete] <cluster> <region> <role_arn> <namespace|-> <ref...>}"
region="${2:?region required}"
role_arn="${3:?role_arn required}"
ns="${4:?namespace or - required}"
shift 4

kcfg="$(mktemp)"
trap 'rm -f "$kcfg"' EXIT

if ! aws eks update-kubeconfig --name "$cluster" --region "$region" --role-arn "$role_arn" \
  --kubeconfig "$kcfg" >/dev/null 2>&1; then
  echo "k8s-finalizer-clear: cluster '$cluster' unreachable (likely already destroyed) — nothing to clear"
  exit 0
fi

nsflag=()
[ "$ns" != "-" ] && nsflag=(-n "$ns")

for ref in "$@"; do
  # Resolve each ref to concrete "kind/name" targets. `kubectl patch` does NOT support --all (only get/delete
  # do), so a kind-only ref must be enumerated first via `get -o name` (which prints kind/name lines) — patching
  # `<kind> --all` silently errors and the finalizer is never cleared. Word-split is safe (k8s names have no
  # spaces); avoid mapfile/readarray (bash 4+, absent on macOS bash 3.2).
  if [[ "$ref" == */* ]]; then
    names=("$ref")
  else
    # shellcheck disable=SC2207
    names=($(kubectl --kubeconfig "$kcfg" ${nsflag[@]+"${nsflag[@]}"} get "$ref" -o name 2>/dev/null))
  fi

  if [ "${#names[@]}" -eq 0 ]; then
    echo "k8s-finalizer-clear: none present: ${ref}"
    continue
  fi

  for name in "${names[@]}"; do
    # Optionally delete first so the finalizer strip forces removal of a resource nothing else is deleting.
    # --wait=false is ESSENTIAL: a finalizer-blocked CR won't actually delete until the patch below runs, so a
    # waiting delete would block forever before reaching it. --force --grace-period=0 additionally evicts pods
    # stuck Terminating with no finalizer (kubelet never confirmed) — the patch alone can't touch those.
    if [ "$do_delete" = "1" ]; then
      kubectl --kubeconfig "$kcfg" ${nsflag[@]+"${nsflag[@]}"} delete "$name" \
        --wait=false --force --grace-period=0 --ignore-not-found >/dev/null 2>&1 || true
    fi
    if kubectl --kubeconfig "$kcfg" ${nsflag[@]+"${nsflag[@]}"} patch "$name" \
      --type=merge -p '{"metadata":{"finalizers":null}}' >/dev/null 2>&1; then
      echo "k8s-finalizer-clear: cleared finalizers on ${name}"
    else
      echo "k8s-finalizer-clear: nothing to clear: ${name}"
    fi
  done
done

exit 0
