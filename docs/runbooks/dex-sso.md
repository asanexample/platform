# Runbook: Dex SSO Broker

> **Identity Provider:** AWS Identity Center (SAML 2.0 via Dex)
> **Issuer / URL:** `https://sso.aws.refplat.org` (requires Tailscale VPN)
> **First client:** Backstage (`https://backstage.aws.refplat.org`)
>
> **Last reviewed:** 2026-06-03

---

## Table of Contents

1. [Overview](#overview)
2. [Initial Setup](#initial-setup)
3. [Adding Another OIDC Client](#adding-another-oidc-client)
4. [Authorization Boundary](#authorization-boundary)
5. [Certificate Rotation](#certificate-rotation)
6. [Troubleshooting](#troubleshooting)

---

## Overview

Dex is a **centralized SAML→OIDC broker** (ADR-052): one Dex instance bridges AWS Identity Center (SAML IdP)
to many OIDC clients. Unlike ArgoCD's *embedded* Dex (ADR-012), this is a standalone deployment
(`infra/modules/dex` + the `dex` unit) so that Backstage — and future apps — share one Identity Center SAML
app and one certificate. The SAML application in Identity Center cannot be managed via Terraform (provider
limitation) and is configured manually, once.

```text
Browser -> Backstage "Sign in with AWS SSO"
  -> OIDC to Dex (sso.aws.refplat.org)
  -> Dex (SAML SP) -> redirect to Identity Center (SAML IdP)
  -> User authenticates
  -> SAML assertion (email + groups) -> Dex
  -> Dex issues an OIDC token -> Backstage
```

Dex listens HTTP on 5556; TLS is terminated at the Cilium Gateway (internal NLB, Tailscale-only). Storage is
CRD-backed (`kubernetes`), shared across 2 replicas.

---

## Initial Setup

The SAML application must be created manually in the Identity Center console. This is a **separate** SAML app
from ArgoCD's — it has its own ACS URL and therefore its own signing certificate.

### Step 1: Create the SAML application

1. Open the [IAM Identity Center console](https://console.aws.amazon.com/singlesignon) in the management
   account (`<MGMT_ACCOUNT_ID>`)
2. Navigate to **Applications** -> **Add application**
3. Select **I have an application I want to set up** -> **SAML 2.0**
4. Configure:
   - **Display name:** `Dex (Platform SSO)`
   - **Application ACS URL:** `https://sso.aws.refplat.org/callback`
   - **Application SAML audience:** `https://sso.aws.refplat.org/callback`

(Both must equal `<issuer>/callback`. The module derives this from `dex_issuer` as the SAML connector's
`redirectURI`/`entityIssuer`.)

### Step 2: Configure attribute mappings

| Attribute | Value | Format |
|-----------|-------|--------|
| `Subject` | `${user:email}` | emailAddress |
| `email` | `${user:email}` | unspecified |
| `groups` | `${user:groups}` | unspecified |

The `groups` attribute is plumbed through for future group-based RBAC. Use "unspecified" format so Identity
Center sends short attribute names (`email`, `groups`) — the Dex SAML connector uses those short names
(`usernameAttr`/`emailAttr = email`, `groupsAttr = groups`), not full SAML URIs.

### Step 3: Assign groups (the authorization boundary)

Assign the application to the intended Identity Center groups only — see
[Authorization Boundary](#authorization-boundary). For Phase 2.1, that's:

- Admins
- Developers-alpha / Developers-bravo (per-team developer groups)
- ReadOnly

### Step 4: Extract values for `secrets.hcl`

1. Copy the **IAM Identity Center SAML sign-in URL** from the application details.
2. Download the **SAML metadata XML** from the application details.
3. Extract the certificate from the `<ds:X509Certificate>` element, wrap in PEM headers, and base64-encode:

```bash
xmllint --xpath '//*[local-name()="X509Certificate"]/text()' metadata.xml \
  | fold -w 64 \
  | { echo "-----BEGIN CERTIFICATE-----"; cat; echo "-----END CERTIFICATE-----"; } \
  > signing-cert.pem
base64 -i signing-cert.pem | tr -d '\n'
```

> **Warning:** Do NOT use the certificate from the console's "Download certificate" button — it can differ
> from the actual signing certificate. Always extract it from the SAML metadata XML.

1. Add both values to `infra/live/aws/secrets.hcl` (gitignored; see `secrets.hcl.example`):

```hcl
dex_sso_url     = "<SAML sign-in URL>"
dex_sso_ca_data = "<base64-encoded certificate>"
```

### Step 5: Deploy

```bash
# Platform account; assumes PlatformDeployer (aws sso login --profile management if expired).
cd infra/live/aws/platform/us-east-1/platform/dex
terragrunt apply

# Then expose it (adds the sso.aws.refplat.org HTTPRoute):
cd ../gateway-config && terragrunt apply
```

Verify the discovery document, then deploy/roll Backstage:

```bash
curl -s https://sso.aws.refplat.org/.well-known/openid-configuration | jq '.issuer, .authorization_endpoint'
```

---

## Adding Another OIDC Client

No new SAML app or certificate is needed — add a client to the broker:

1. Append an entry to the `static_clients` input of the `dex` module (id, name, redirect_uris, secret_env).
   The module generates its secret (`platform/<id>/oidc`), syncs it into the `dex` namespace, and injects it.
2. `terragrunt apply` the `dex` unit. The new app reads the same Secrets Manager path via its own
   ExternalSecret and points its OIDC config at `https://sso.aws.refplat.org`.

---

## Authorization Boundary

Phase 2.1 is **login-only**: Backstage's sign-in resolver issues an identity straight from the email claim
(`dangerouslyAllowSignInWithoutUserInCatalog`) and there is no permission framework yet, so **any Identity
Center user assigned the Dex SAML app can log in and read the portal**. The real authorization gate is
therefore the **SAML app's group assignment** (Step 3) — keep it scoped to the intended groups, not org-wide.
Group-based RBAC (mapping the `groups` claim to elevated access) is a later-phase item.

---

## Certificate Rotation

Identity Center certificates expire periodically. When rotated:

1. Download the **SAML metadata XML** from the Dex application.
2. Extract + encode the certificate (see Step 4).
3. Update `dex_sso_ca_data` in `infra/live/aws/secrets.hcl`.
4. Re-apply: `cd dex && terragrunt apply`.

A change to the Dex config rolls the pods automatically.

---

## Troubleshooting

### Redirect loop / "invalid redirect_uri"

**Cause:** The client's redirect URI is not in the Dex `staticClients` allow-list, or the SAML connector's
`redirectURI` doesn't match the Identity Center ACS URL.

**Fix:** The Backstage client redirect must be exactly
`https://backstage.aws.refplat.org/api/auth/oidc/handler/frame`; the SAML ACS and Dex `redirectURI`/
`entityIssuer` must both be exactly `https://sso.aws.refplat.org/callback`.

### Dex pod CrashLoopBackOff

```bash
kubectl --context platform logs -n dex -l app.kubernetes.io/name=dex
```

- `failed to load connector`: SSO URL wrong or certificate malformed.
- `x509: certificate signed by unknown authority`: `dex_sso_ca_data` missing or incorrectly encoded.
- API-server/RBAC errors creating CRDs: confirm `rbac.createClusterScoped` is on (kubernetes storage needs it).

### Backstage shows "Sign in" but the popup errors

**Cause:** The OIDC client secret in the `dex` namespace and the `backstage` namespace differ, or the
ExternalSecret hasn't synced.

**Fix:**

```bash
kubectl --context platform get externalsecret -n dex
kubectl --context platform get externalsecret -n backstage
# Both dex-backstage-oidc and backstage-oidc must be SecretSynced and carry the same value.
```

### "no attribute with name" error

**Cause:** `usernameAttr`/`emailAttr`/`groupsAttr` don't match the SAML assertion's attribute names. Identity
Center sends short names (`email`, `groups`) when the attribute format is "unspecified"/"basic".

**Fix:** Keep the short names in the connector config (the module already uses them).

### Discovery document unreachable / Backstage sign-in 500 `getaddrinfo ENOTFOUND sso.aws.refplat.org`

```bash
curl -sv https://sso.aws.refplat.org/.well-known/openid-configuration
# Confirm the record is actually published (bypass caches — query the zone's authoritative NS):
dig +short A sso.aws.refplat.org @"$(dig +short NS aws.refplat.org | head -1)"
```

- **Stale negative DNS cache (most common right after first deploy):** if the authoritative query above returns
  the NLB IPs but the normal resolver (and the Backstage pod) returns nothing, the name was queried **before**
  external-dns created the record, so resolvers cached an NXDOMAIN. `aws.refplat.org`'s SOA caps that at **15
  minutes** — just wait it out and retry; nothing is misconfigured. **Avoid curling the hostname before the
  gateway-config apply runs** (that's what poisons the cache). CoreDNS only caches 30s; the holder is the upstream
  VPC/Route53 resolver, which can't be flushed — time is the fix.
- DNS missing entirely: external-dns creates the record from the `sso` HTTPRoute — confirm the gateway-config apply ran.
- TLS error: the `*.aws.refplat.org` wildcard cert on the gateway covers `sso`; check cert-manager.
- 404/connection refused: confirm the `sso` route backend is `dex:5556` and the Dex Service exists.
- **NLB hairpin (if DNS resolves but the backend still can't reach Dex):** the backstage pod reaches Dex by
  hairpinning out to the internal NLB and back in. If the token/discovery call hangs or resets only from in-cluster,
  suspect NLB loopback; the gateway NLB should use `target-type: ip` (Cilium gateway pods) which generally avoids it.
