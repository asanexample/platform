#!/usr/bin/env bash
# kc-portforward.sh — manage a background kubectl port-forward to the Keycloak Service so keycloak-config can
# configure Keycloak over localhost (in-cluster), with NO dependency on the Tailscale-fronted gateway (ADR-059).
#
# It reaches the cluster API the same way Terragrunt does (aws eks + the deployer role); the EKS endpoint is
# public during bootstrap (use an SSM tunnel — scripts/eks-tunnel.sh — for a locked-down day-2 cluster). A
# throwaway kubeconfig is used (never ~/.kube/config). State (pid + temp kubeconfig) is keyed by cluster+port.
#
# Usage:
#   kc-portforward.sh up   <cluster> <region> <role_arn> <namespace> <service> <remote_port> <local_port>
#   kc-portforward.sh down <cluster> <local_port>
set -euo pipefail

mode="${1:?usage: kc-portforward.sh up|down ...}"
shift

statedir="${TMPDIR:-/tmp}"
statedir="${statedir%/}"

case "$mode" in
up)
  cluster="${1:?up: <cluster> <region> <role_arn> <namespace> <service> <remote_port> <local_port>}"
  region="${2:?region required}"
  role_arn="${3:?role_arn required}"
  ns="${4:?namespace required}"
  svc="${5:?service required}"
  remote_port="${6:?remote_port required}"
  local_port="${7:?local_port required}"

  pidf="${statedir}/kc-pf-${cluster}-${local_port}.pid"
  kcfg="${statedir}/kc-pf-${cluster}-${local_port}.kubeconfig"
  logf="${statedir}/kc-pf-${cluster}-${local_port}.log"

  # Clear any stale port-forward from a prior run.
  if [ -f "$pidf" ]; then
    kill "$(cat "$pidf")" 2>/dev/null || true
    rm -f "$pidf"
  fi

  # Throwaway kubeconfig. Auth mirrors the units' exec-auth: the deployer role + ambient AWS creds.
  rm -f "$kcfg"
  aws eks update-kubeconfig --name "$cluster" --region "$region" --role-arn "$role_arn" --kubeconfig "$kcfg" >/dev/null

  echo "kc-portforward: port-forward svc/${svc} (ns ${ns}) localhost:${local_port} -> ${remote_port} [${cluster}]"
  # nohup (not setsid — macOS lacks setsid) so the forward survives this script exiting.
  nohup kubectl --kubeconfig "$kcfg" -n "$ns" port-forward "svc/${svc}" "${local_port}:${remote_port}" \
    >"$logf" 2>&1 &
  echo $! >"$pidf"

  # Wait until Keycloak actually serves over the forward; on failure, tear down our own pf and fail loudly.
  scriptdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if ! "${scriptdir}/wait-for-http.sh" \
    "http://localhost:${local_port}/realms/master/.well-known/openid-configuration" 180 5; then
    echo "kc-portforward: Keycloak not reachable over the port-forward — tearing down" >&2
    kill "$(cat "$pidf")" 2>/dev/null || true
    rm -f "$pidf"
    echo "--- port-forward log ---" >&2
    cat "$logf" >&2 || true
    exit 1
  fi
  echo "kc-portforward: ready on localhost:${local_port}"
  ;;

down)
  cluster="${1:?down: <cluster> <local_port>}"
  local_port="${2:?local_port required}"
  pidf="${statedir}/kc-pf-${cluster}-${local_port}.pid"
  kcfg="${statedir}/kc-pf-${cluster}-${local_port}.kubeconfig"
  if [ -f "$pidf" ]; then
    kill "$(cat "$pidf")" 2>/dev/null || true
    rm -f "$pidf"
    echo "kc-portforward: stopped port-forward [${cluster}:${local_port}]"
  fi
  rm -f "$kcfg"
  ;;

*)
  echo "usage: kc-portforward.sh up|down ..." >&2
  exit 1
  ;;
esac
