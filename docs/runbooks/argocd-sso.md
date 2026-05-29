# Runbook: ArgoCD SSO

> **Identity Provider:** AWS Identity Center (SAML 2.0 via Dex)
> **URL:** `https://argocd.aws.refplat.org` (requires Tailscale VPN)
>
> **Last reviewed:** 2026-05-21

---

## Table of Contents

1. [Overview](#overview)
2. [Initial Setup](#initial-setup)
3. [RBAC Group Mapping](#rbac-group-mapping)
4. [Certificate Rotation](#certificate-rotation)
5. [Troubleshooting](#troubleshooting)

---

## Overview

ArgoCD authenticates users via AWS Identity Center using SAML 2.0. Dex
(bundled with the ArgoCD Helm chart) acts as a SAML-to-OIDC bridge. The
SAML application in Identity Center cannot be managed via Terraform (provider
limitation) and is configured manually.

```text
Browser -> ArgoCD "Log in via SSO"
  -> Dex (SAML SP) -> redirect to Identity Center (SAML IdP)
  -> User authenticates
  -> SAML assertion (email + groups) -> Dex
  -> Dex maps groups -> ArgoCD RBAC
```

---

## Initial Setup

The SAML application must be created manually in the Identity Center console.

### Step 1: Create the SAML application

1. Open the [IAM Identity Center console](https://console.aws.amazon.com/singlesignon)
   in the management account (<MGMT_ACCOUNT_ID>)
2. Navigate to **Applications** -> **Add application**
3. Select **I have an application I want to set up** -> **SAML 2.0**
4. Configure:
   - **Display name:** `ArgoCD`
   - **Application ACS URL:** `https://argocd.aws.refplat.org/api/dex/callback`
   - **Application SAML audience:** `https://argocd.aws.refplat.org/api/dex/callback`

### Step 2: Configure attribute mappings

In the application settings, add these attribute mappings:

| Attribute | Value | Format |
|-----------|-------|--------|
| `Subject` | `${user:email}` | emailAddress |
| `email` | `${user:email}` | unspecified |
| `groups` | `${user:groups}` | unspecified |

The `groups` attribute is critical -- without it, users authenticate but
all get the default `role:readonly` with no group-based permissions.

Use "unspecified" format so Identity Center sends short attribute names
(`email`, `groups`). The Dex SAML connector config must use matching short
names -- do NOT use full SAML URI format.

### Step 3: Assign groups

Assign all three Identity Center groups to the application:

- Admins
- Developers
- ReadOnly

### Step 4: Extract values for Terraform

1. Copy the **IAM Identity Center SAML sign-in URL** from the application details
2. Download the **SAML metadata XML** from the application details
3. Extract the certificate from the `<ds:X509Certificate>` element in the
   metadata XML, wrap it in PEM headers, and base64-encode:

```bash
# Extract cert from metadata XML → PEM → base64
xmllint --xpath '//*[local-name()="X509Certificate"]/text()' metadata.xml \
  | fold -w 64 \
  | { echo "-----BEGIN CERTIFICATE-----"; cat; echo "-----END CERTIFICATE-----"; } \
  > signing-cert.pem
base64 -i signing-cert.pem | tr -d '\n'
```

> **Warning:** Do NOT use the certificate downloaded from the Identity Center
> console ("Download certificate" button). It can differ from the actual
> signing certificate. Always extract the certificate from the SAML metadata
> XML, which contains the exact certificate used to sign SAML responses.

1. Add both values to `infra/live/aws/common.hcl`:

```hcl
argocd_sso_url     = "<SAML sign-in URL>"
argocd_sso_ca_data = "<base64-encoded certificate>"
```

### Step 5: Deploy

```bash
cd infra/live/aws/platform/us-east-1/platform/argocd
terragrunt apply
```

---

## RBAC Group Mapping

Identity Center sends group IDs (UUIDs), not display names, in the SAML
assertion. The RBAC policy maps these UUIDs to ArgoCD roles:

| Identity Center Group | Group ID | ArgoCD Role | Permissions |
|----------------------|----------|-------------|-------------|
| Admins | `a4b884e8-f021-7042-5f38-65d571afff7c` | `role:admin` | Full admin access |
| Developers | `a4c85418-d071-7051-9bee-c5a90ee7963e` | `role:developer` | App get/sync, logs |
| ReadOnly | `c4b87428-8051-7073-9af0-a31f4b94daac` | `role:readonly` | Read-only |

To find group IDs:

```bash
AWS_PROFILE=management aws identitystore list-groups \
  --identity-store-id <identity-store-id> \
  --query 'Groups[].{Name:DisplayName,Id:GroupId}' --output table
```

RBAC policies are defined in:

```text
infra/live/aws/platform/us-east-1/platform/argocd/terragrunt.hcl
```

---

## Certificate Rotation

Identity Center certificates expire periodically. When the certificate is
rotated:

1. Download the **SAML metadata XML** from the Identity Center application
2. Extract and encode the certificate from the metadata (see Step 4 above)
3. Update `argocd_sso_ca_data` in `infra/live/aws/common.hcl`
4. Re-apply: `cd argocd && terragrunt apply`

The `configHash` in the Helm release triggers an automatic pod restart.

---

## Troubleshooting

### "Log in via SSO" button not visible

**Cause:** Dex is not enabled in the ArgoCD deployment.

**Fix:** Verify `dex_enabled = true` in the ArgoCD unit and re-apply.

```bash
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-dex-server
```

### Redirect loop after Identity Center login

**Cause:** The `redirectURI` in the Dex SAML config does not match the
ACS URL configured in the Identity Center SAML app.

**Fix:** Both must be exactly `https://argocd.aws.refplat.org/api/dex/callback`.

### Login succeeds but user has no permissions

**Cause:** Group attribute mapping is missing in the Identity Center SAML
app, or `rbac.scopes` is not set to `[groups]` in ArgoCD.

**Fix:**

1. Verify the SAML app has `groups` -> `${user:groups}` attribute mapping
2. Verify `rbac_scopes = "[groups]"` in the ArgoCD unit
3. Check the user's group membership in Identity Center

### Dex pod CrashLoopBackOff

**Cause:** Invalid SAML configuration (wrong SSO URL, malformed certificate).

**Fix:**

```bash
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-dex-server
```

Common errors:

- `failed to load connector`: certificate is invalid or SSO URL is wrong
- `x509: certificate signed by unknown authority`: `caData` is missing or
  incorrectly encoded

### "Could not verify certificate against trusted certs"

**Cause:** The certificate in `argocd_sso_ca_data` does not match the
certificate Identity Center uses to sign SAML responses. This commonly
happens when the certificate is downloaded from the console UI instead of
extracted from the SAML metadata XML -- the two can differ.

**Fix:** Extract the certificate from the SAML metadata XML (see Step 4
in Initial Setup), update `common.hcl`, and re-apply.

### "no attribute with name" error

**Cause:** The `usernameAttr`/`emailAttr`/`groupsAttr` in the Dex config
do not match the attribute names in the SAML assertion. Identity Center
sends short names (`email`, `groups`) when attribute format is set to
"unspecified" or "basic", not full SAML URIs.

**Fix:** Use short attribute names in the Dex SAML connector config:
`usernameAttr = "email"`, `emailAttr = "email"`, `groupsAttr = "groups"`.

### "Failed to authenticate" after certificate rotation

**Cause:** The `argocd_sso_ca_data` in `common.hcl` does not match the
current Identity Center certificate.

**Fix:** Extract the certificate from the SAML metadata XML (see Step 4
in Initial Setup), update `common.hcl`, and re-apply.

### Break-glass: local admin login

If SSO is unavailable, use the local admin account:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

Log in with username `admin` and the retrieved password.
