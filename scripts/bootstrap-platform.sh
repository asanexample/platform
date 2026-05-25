#!/usr/bin/env bash
#
# Bootstrap the full AWS platform stack from zero.
#
# Prerequisites:
#   - AWS credentials configured (aws sso login)
#   - Cloudflare API token stored in Secrets Manager (platform/cloudflare/api-token)
#   - Management account state backend already provisioned
#   - IAM roles must exist before first run. On a fresh account, bootstrap
#     iam-roles manually first:
#       AWS_PROFILE=platform terragrunt apply -auto-approve \
#         -chdir=infra/live/aws/platform/us-east-1/platform/iam-roles
#
# Usage:
#   AWS_PROFILE=management ./scripts/bootstrap-platform.sh [-y|--yes]
#
# Options:
#   -y, --yes    Non-interactive mode. Skips manual step prompts (assumes
#                prerequisites like Tailscale API key and ArgoCD SAML app
#                are already configured). Fails if they are not.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$REPO_ROOT/scripts/lib/common.sh"

UNIT_DIR="$REPO_ROOT/infra/live/aws/platform/us-east-1/platform"
CLUSTER_NAME="platform-use1-eks"
REGION="us-east-1"
INTERACTIVE=true

for arg in "$@"; do
  case "$arg" in
    -y|--yes) INTERACTIVE=false ;;
  esac
done

log_info "=== AWS Platform Bootstrap ==="
if [[ "$INTERACTIVE" == false ]]; then
  log_info "Running in non-interactive mode (--yes)"
fi
log_info ""

check_prerequisites

# ─────────────────────────────────────────────────────────────────────────────
# Phase 1 — Foundation (parallel, no dependencies)
# ─────────────────────────────────────────────────────────────────────────────

log_info "Phase 1/15: Deploying IAM roles, networking, and Route53..."
run_tg_parallel "$UNIT_DIR/iam-roles" "$UNIT_DIR/networking" "$UNIT_DIR/route53"

# ─────────────────────────────────────────────────────────────────────────────
# Phase 2 — Cloudflare NS delegation (needs route53 NS records)
# ─────────────────────────────────────────────────────────────────────────────

log_info "Phase 2/15: Delegating DNS to Route53 via Cloudflare..."
run_tg "$UNIT_DIR/cloudflare-dns"

# ─────────────────────────────────────────────────────────────────────────────
# Phase 3 — EKS cluster (public endpoint enabled for bootstrap)
#
# The cluster is normally private-only (endpoint_public_access=false in
# terragrunt.hcl). During bootstrap, Tailscale VPN isn't deployed yet, so we
# temporarily enable the public endpoint. Phase 15 locks it back down.
# ─────────────────────────────────────────────────────────────────────────────

log_info "Phase 3/15: Deploying EKS cluster (public endpoint enabled for bootstrap)..."
run_tg "$UNIT_DIR/eks" apply -var 'endpoint_public_access=true'

# ─────────────────────────────────────────────────────────────────────────────
# Phase 4 — Cilium CNI (BYOCNI — must be installed before nodes join)
# ─────────────────────────────────────────────────────────────────────────────

log_info "Phase 4/15: Deploying Cilium CNI..."
run_tg "$UNIT_DIR/cilium"

# ─────────────────────────────────────────────────────────────────────────────
# Phase 5 — Managed node groups (need Cilium ready first)
# ─────────────────────────────────────────────────────────────────────────────

log_info "Phase 5/15: Deploying managed node groups..."
run_tg "$UNIT_DIR/node-groups"

# ─────────────────────────────────────────────────────────────────────────────
# Phase 6 — Post-node services (parallel)
# ─────────────────────────────────────────────────────────────────────────────

log_info "Phase 6/15: Deploying EKS addons and SSM bastion..."
run_tg_parallel "$UNIT_DIR/eks-addons" "$UNIT_DIR/ssm-bastion"

# ─────────────────────────────────────────────────────────────────────────────
# Phase 7 — Manual: Tailscale account + API key
# ─────────────────────────────────────────────────────────────────────────────

if secret_exists "platform/tailscale/api-key" platform; then
  log_success "Phase 7/15: Tailscale API key already in Secrets Manager — skipping."
elif [[ "$INTERACTIVE" == true ]]; then
  prompt_manual_step "Tailscale Account Setup" <<'INSTRUCTIONS'
1. Create a Tailscale account at https://login.tailscale.com

2. Generate an API key:
   Admin console → Settings → Keys → Generate API key

3. Store the API key in AWS Secrets Manager:

   aws secretsmanager create-secret \
     --name platform/tailscale/api-key \
     --secret-string '<API_KEY>' \
     --region us-east-1 --profile platform

   If the secret already exists, use put-secret-value instead.
INSTRUCTIONS
  validate_secret "platform/tailscale/api-key" platform
else
  log_error "Phase 7/15: Secret platform/tailscale/api-key not found and --yes was passed."
  log_error "Create the secret first, then re-run."
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# Phase 8 — Tailscale admin (ACL policy + OAuth client)
#
# Creates the tailnet ACL policy and an OAuth client. The OAuth client
# credentials are automatically stored in Secrets Manager as
# platform/tailscale/oauth — the tailscale unit reads them later.
# ─────────────────────────────────────────────────────────────────────────────

log_info "Phase 8/15: Deploying Tailscale admin configuration..."
run_tg "$UNIT_DIR/tailscale-admin"

# ─────────────────────────────────────────────────────────────────────────────
# Phase 9 — Platform services (parallel)
# ─────────────────────────────────────────────────────────────────────────────

log_info "Phase 9/15: Deploying cert-manager, external-dns, external-secrets..."
run_tg_parallel "$UNIT_DIR/cert-manager" "$UNIT_DIR/external-dns" "$UNIT_DIR/external-secrets"

# ─────────────────────────────────────────────────────────────────────────────
# Phase 10 — Secret stores (ClusterSecretStore CRDs)
#
# Deploys ClusterSecretStore resources backed by AWS Secrets Manager and
# SSM Parameter Store. Runs after external-secrets (Phase 9) which installs
# the ESO CRDs.
# ─────────────────────────────────────────────────────────────────────────────

log_info "Phase 10/15: Deploying ClusterSecretStore configuration..."
run_tg "$UNIT_DIR/secret-stores"

# ─────────────────────────────────────────────────────────────────────────────
# Phase 11 — Tailscale operator (two-stage for CRD bootstrap)
#
# The module uses kubernetes_manifest for ProxyClass and Connector CRDs.
# These CRDs are installed by the Helm chart, so on a fresh cluster they
# don't exist yet and a full apply would fail at plan time. Stage 1 installs
# the chart (which registers the CRDs), then stage 2 creates the CR instances.
# ─────────────────────────────────────────────────────────────────────────────

if k8s_crd_exists "connectors.tailscale.com"; then
  log_info "Phase 11/15: Tailscale CRDs already registered — running full apply..."
  run_tg "$UNIT_DIR/tailscale"
else
  log_info "Phase 11/15: Deploying Tailscale operator (stage 1: Helm chart)..."
  run_tg "$UNIT_DIR/tailscale" apply -target='helm_release.tailscale_operator[0]'

  log_info "Phase 11/15: Deploying Tailscale operator (stage 2: Connector + split DNS)..."
  run_tg "$UNIT_DIR/tailscale"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Phase 12 — Manual: ArgoCD SAML app in Identity Center
# ─────────────────────────────────────────────────────────────────────────────

if grep -q 'argocd_sso_url.*portal\.sso' "$REPO_ROOT/infra/live/aws/common.hcl" 2>/dev/null; then
  log_success "Phase 12/15: ArgoCD SSO URL found in common.hcl — skipping."
elif [[ "$INTERACTIVE" == true ]]; then
  prompt_manual_step "ArgoCD SSO Setup" <<'INSTRUCTIONS'
Create a SAML application in AWS Identity Center:

1. AWS SSO Console → Applications → Add application
2. "I have an application I want to set up" → SAML 2.0
3. Display name: ArgoCD
4. ACS URL: https://argocd.aws.refplat.org/api/dex/callback
5. Audience: https://argocd.aws.refplat.org/api/dex/callback
6. Attribute mappings:
   - Subject → ${user:email}  (emailAddress)
   - email   → ${user:email}  (unspecified)
   - groups  → ${user:groups} (unspecified)
7. Assign users/groups to the application

After creating the app, update infra/live/aws/common.hcl with:
  argocd_sso_url     = "<SSO URL from the SAML app>"
  argocd_sso_ca_data = "<base64-encoded CA certificate>"
INSTRUCTIONS
else
  log_error "Phase 12/15: ArgoCD SSO URL not found in common.hcl and --yes was passed."
  log_error "Create the SAML app and update common.hcl first, then re-run."
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# Phase 13 — ArgoCD
# ─────────────────────────────────────────────────────────────────────────────

log_info "Phase 13/15: Deploying ArgoCD..."
run_tg "$UNIT_DIR/argocd"

# ─────────────────────────────────────────────────────────────────────────────
# Phase 14 — Gateway config (final leaf node)
# ─────────────────────────────────────────────────────────────────────────────

log_info "Phase 14/15: Deploying Gateway configuration..."
run_tg "$UNIT_DIR/gateway-config"

# ─────────────────────────────────────────────────────────────────────────────
# Phase 15 — Lock down EKS to private-only endpoint
#
# Re-applies the EKS unit without the -var override. The terragrunt.hcl
# specifies endpoint_public_access=false, so this disables public access.
# After this, all API access goes through Tailscale VPN.
# ─────────────────────────────────────────────────────────────────────────────

if eks_endpoint_is_private_only "$CLUSTER_NAME" "$REGION"; then
  log_success "Phase 15/15: EKS endpoint is already private-only — skipping."
else
  log_info "Phase 15/15: Locking down EKS to private-only endpoint..."
  run_tg "$UNIT_DIR/eks"
fi

echo ""
log_success "=== Bootstrap complete! ==="
log_info "Next steps:"
log_info "  1. Connect to Tailscale (tailscale up)"
log_info "  2. Configure kubectl:"
log_info "     aws eks update-kubeconfig --name platform-use1-eks --region us-east-1 --role-arn arn:aws:iam::829808296602:role/PlatformAdmin"
log_info "  3. Verify: kubectl get nodes"
