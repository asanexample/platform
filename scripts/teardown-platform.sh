#!/usr/bin/env bash
#
# Tear down the full AWS platform stack in reverse dependency order.
#
# By default, the Route53 hosted zone is preserved (destroying it would
# require re-creating the Cloudflare NS delegation). Pass --include-route53
# to destroy it as well.
#
# Usage:
#   ./scripts/teardown-platform.sh [--include-route53]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$REPO_ROOT/scripts/lib/common.sh"

UNIT_DIR="$REPO_ROOT/infra/live/aws/platform/us-east-1/platform"
INCLUDE_ROUTE53=false
[[ "${1:-}" == "--include-route53" ]] && INCLUDE_ROUTE53=true

log_info "=== AWS Platform Teardown ==="
log_info ""

check_prerequisites

# ─────────────────────────────────────────────────────────────────────────────
# Confirmation
# ─────────────────────────────────────────────────────────────────────────────

log_warn "This will DESTROY all platform resources in us-east-1."
if [[ "$INCLUDE_ROUTE53" == true ]]; then
  log_warn "Route53 hosted zone WILL be destroyed (--include-route53)."
fi
echo ""
log_warn "Type DESTROY to confirm:"
read -r confirmation
if [[ "$confirmation" != "DESTROY" ]]; then
  log_error "Aborted."
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# Phase 1 — Destroy Tailscale and gateway-config while VPN is still active
#
# The EKS API is private-only. Tailscale provides access via split DNS and
# subnet routing. We must destroy K8s resources that depend on Tailscale CRDs
# BEFORE removing VPN access. Gateway-config is a leaf node, so destroy it
# here too.
# ─────────────────────────────────────────────────────────────────────────────

log_info "Destroying gateway-config and tailscale (while VPN is active)..."
run_tg "$UNIT_DIR/gateway-config" destroy
run_tg "$UNIT_DIR/tailscale" destroy
run_tg "$UNIT_DIR/tailscale-admin" destroy

# ─────────────────────────────────────────────────────────────────────────────
# Phase 2 — Switch to public endpoint
#
# With Tailscale destroyed, the split DNS route is gone and the VPN tunnel
# is down. Enable the public API endpoint so Terragrunt can reach the
# cluster for the remaining destroys.
# ─────────────────────────────────────────────────────────────────────────────

log_warn "Enabling public endpoint for remaining teardown..."
run_tg "$UNIT_DIR/eks" apply -var 'endpoint_public_access=true'

log_warn "Waiting 5 minutes for endpoint update + DNS propagation..."
sleep 300

# ─────────────────────────────────────────────────────────────────────────────
# Phase 3 — Destroy remaining K8s services via public endpoint
# ─────────────────────────────────────────────────────────────────────────────

log_info "Destroying argocd..."
run_tg "$UNIT_DIR/argocd" destroy

log_info "Destroying platform services..."
run_tg_destroy_parallel "$UNIT_DIR/cert-manager" "$UNIT_DIR/external-dns" "$UNIT_DIR/external-secrets"

log_info "Destroying EKS addons and SSM bastion..."
run_tg_destroy_parallel "$UNIT_DIR/eks-addons" "$UNIT_DIR/ssm-bastion"

log_info "Destroying node groups..."
run_tg "$UNIT_DIR/node-groups" destroy

log_info "Destroying Cilium..."
run_tg "$UNIT_DIR/cilium" destroy

log_info "Destroying EKS cluster..."
run_tg "$UNIT_DIR/eks" destroy

log_info "Destroying Cloudflare DNS delegation..."
run_tg "$UNIT_DIR/cloudflare-dns" destroy

if [[ "$INCLUDE_ROUTE53" == true ]]; then
  log_info "Destroying Route53 hosted zone..."
  run_tg "$UNIT_DIR/route53" destroy
fi

log_info "Destroying networking and IAM roles..."
run_tg_destroy_parallel "$UNIT_DIR/networking" "$UNIT_DIR/iam-roles"

echo ""
log_success "=== Teardown complete! ==="
if [[ "$INCLUDE_ROUTE53" == false ]]; then
  log_warn "Route53 zone preserved. Destroy manually if needed:"
  log_warn "  cd $UNIT_DIR/route53 && terragrunt destroy"
fi
