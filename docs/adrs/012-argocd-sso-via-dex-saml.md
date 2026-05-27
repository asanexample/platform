# ADR-012: ArgoCD SSO via Dex and SAML

**Date:** 2026-05-23

**Status:** Accepted

## Context

ArgoCD is deployed on the platform EKS cluster for GitOps-based application delivery. By default,
ArgoCD uses a local admin account with a generated password stored in a Kubernetes secret. This
is adequate for initial setup but insufficient for a multi-user platform:

1. **No identity integration.** Users must share the admin password or create local ArgoCD accounts.
   There's no connection to the organization's identity provider (AWS Identity Center / IAM Identity
   Center).

2. **No group-based RBAC.** ArgoCD RBAC policies can reference users and groups, but without SSO,
   there are no groups — only individual local accounts. Role assignments must be managed manually
   per user.

3. **No audit trail.** Local account access doesn't produce identity-linked audit logs that tie
   actions to specific organizational users.

The platform uses AWS IAM Identity Center (formerly AWS SSO) as its identity provider. ArgoCD
supports OIDC-based SSO natively, but Identity Center does not expose a standard OIDC endpoint
for custom applications. It does support SAML 2.0 for custom application integration.

### Alternatives Considered

**1. ArgoCD native OIDC with a separate IdP.** Configure ArgoCD to authenticate directly against
an OIDC provider (Okta, Auth0, etc.). This requires introducing a new identity provider separate
from Identity Center, creating a split identity model where AWS access uses Identity Center and
ArgoCD uses something else. Rejected because it adds cost, operational burden, and identity
fragmentation.

**2. AWS Cognito as OIDC bridge.** Create a Cognito User Pool federated with Identity Center, then
configure ArgoCD to use Cognito as its OIDC provider. This keeps identity centralized but adds a
Cognito deployment to manage, has complex federation configuration, and Cognito's group claim
handling requires custom attribute mapping. More moving parts than necessary.

**3. Dex as SAML-to-OIDC bridge (chosen).** Dex is an OIDC identity provider that supports
multiple upstream authentication protocols, including SAML. It's built into ArgoCD's Helm chart
as an optional component — no separate deployment needed. Configure Dex with a SAML connector
pointing at Identity Center, and ArgoCD authenticates users via Dex's OIDC interface while Dex
handles the SAML exchange with Identity Center.

## Decision

Enable Dex (built into the ArgoCD Helm chart) as a SAML-to-OIDC bridge between ArgoCD and AWS
IAM Identity Center.

### Architecture

```text
User browser
  → ArgoCD UI (login button)
  → Dex OIDC authorization endpoint
  → SAML redirect to Identity Center
  → User authenticates via Identity Center
  → SAML assertion (email, groups) returned to Dex
  → Dex issues OIDC token to ArgoCD
  → ArgoCD maps groups to RBAC roles
```

### Configuration

The ArgoCD module is cloud-agnostic. It exposes `dex_enabled`, `rbac_scopes`, and `argocd_cm_extra`
variables. All SAML-specific configuration is injected via the live unit's `argocd_cm_extra` input,
keeping the module reusable across clouds.

The SAML connector configuration in the live unit:

```hcl
dex_enabled = true
rbac_scopes = "[groups]"

argocd_cm_extra = {
  "url" = "https://argocd.taild3190d.ts.net"
  "dex.config" = yamlencode({
    connectors = [{
      type = "saml"
      id   = "aws-sso"
      name = "AWS SSO"
      config = {
        ssoURL             = "<Identity Center SAML endpoint>"
        caData             = "<Identity Center signing certificate>"
        redirectURI        = "https://argocd.taild3190d.ts.net/api/dex/callback"
        entityIssuer       = "https://argocd.taild3190d.ts.net/api/dex/callback"
        nameIDPolicyFormat = "emailAddress"
        usernameAttr       = "email"
        emailAttr          = "email"
        groupsAttr         = "groups"
      }
    }]
  })
}
```

### Identity Center SAML App (Manual)

The SAML application in Identity Center is created manually through the AWS console because the
Terraform AWS provider does not support custom SAML application configuration. The manual steps
are documented in `docs/runbooks/argocd-sso.md`.

### Group-Based RBAC

The SAML assertion includes a `groups` attribute containing the user's Identity Center groups.
Dex passes these through as OIDC group claims. ArgoCD's RBAC policy maps groups to roles:

```csv
g, PlatformAdmins, role:admin
g, Developers, role:readonly
```

The `rbac_scopes = "[groups]"` setting tells ArgoCD to inspect the `groups` claim from the OIDC
token when evaluating RBAC policies.

## Consequences

**Positive:**

- Single identity source — users authenticate with the same Identity Center credentials they use
  for AWS console and CLI access
- Group-based RBAC — ArgoCD roles map to Identity Center groups, no per-user configuration
- No additional infrastructure — Dex runs as a sidecar within the ArgoCD deployment, managed by
  the same Helm chart
- Cloud-agnostic module — the ArgoCD module works on any cloud; only the live unit's SAML config
  is AWS-specific. For Azure, a different connector type (Azure AD OIDC) would be injected via
  the same `argocd_cm_extra` variable
- Audit trail — ArgoCD logs show the authenticated user's email and group memberships

**Negative:**

- SAML app creation is manual — cannot be fully automated with Terraform, creating a
  documentation dependency for initial setup and disaster recovery
- SAML certificate rotation requires coordinated updates between Identity Center and ArgoCD's
  Dex config (caData value)
- Dex adds a component to ArgoCD's pod that can fail independently — if Dex crashes, SSO login
  fails (local admin account still works as fallback)
- SSO URL and CA data are stored in the Terragrunt live config and flow through to Helm values,
  meaning they're visible in Terraform state (encrypted at rest via S3 KMS)

**Risks:**

- If Identity Center is down, Dex cannot authenticate users. ArgoCD's local admin account remains
  available as a break-glass option.
- The SAML signing certificate has an expiration date. If it expires without rotation, SSO silently
  fails. Mitigated by monitoring certificate expiry and documenting the rotation procedure.
