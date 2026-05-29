# Gateway Config

Configures the Cilium Gateway API with an internal NLB, TLS certificates, and HTTP routes for platform services.

## Module

`infra/modules/gateway-config`

## Dependencies

- `eks` -- `../eks`
- `cilium` -- `../cilium`
- `cert_manager` -- `../cert-manager`
- `external_dns` -- `../external-dns`
- `argocd` -- `../argocd`
- `route53` -- `../route53`

## Key Inputs

| Input | Value | Notes |
|-------|-------|-------|
| `domain` | `aws.refplat.org` | |
| `internal` | `true` | NLB uses internal scheme; only reachable via Tailscale VPN |
| `letsencrypt_email` | `admin@example.com` | For Let's Encrypt DNS-01 certificate issuance |
| `route53_hosted_zone_id` | From route53 dependency | Used by cert-manager DNS-01 solver |
| `routes.argocd` | `argocd-server:80` in `argocd` namespace | Exposes ArgoCD UI at `argocd.aws.refplat.org` |

## Commands

```bash
# Plan
AWS_PROFILE=management terragrunt plan

# Apply
AWS_PROFILE=management terragrunt apply
```
