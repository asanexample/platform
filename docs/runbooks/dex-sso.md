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

### Step 2: Configure attribute mappings (do NOT skip — a blank Subject = `Federate 403`)

Edit attribute mappings and set **both** of these. The `Subject` row exists by default but its "Maps to"
field is **empty** — you must fill it. Leaving it blank makes Identity Center fail with `Federate 403 Forbidden`
(surfaced as the generic "No access" page), because it can't build the assertion's NameID.

| User attribute in the application | Maps to (IAM Identity Center) | Format |
|-----------|-------|--------|
| `Subject` | `${user:email}` | **emailAddress** |
| `email` | `${user:email}` | unspecified |

> **Do NOT add a `groups → ${user:groups}` mapping.** Identity Center does **not** support emitting group
> memberships as a SAML attribute that way — it fails the assertion. Dex's connector keeps `groupsAttr: groups`
> but simply receives no groups (Backstage 2.1 is login-only, so that's fine). Group-based in-app RBAC (a later
> phase) needs a different source — Identity Center won't carry it over SAML.

### Step 3: Assign groups (the authorization boundary)

Assign the application to the intended Identity Center groups only — see
[Authorization Boundary](#authorization-boundary). For Phase 2.1, that's:

- Admins
- Developers-alpha / Developers-bravo (per-team developer groups)
- ReadOnly

### Step 4: Extract values for `secrets.hcl`

**`dex_sso_url`** — the SAML sign-in URL. Copy it from the app details, OR derive it via CLI (it's
`base64("<account>_ins-<app-ARN-suffix>")`; get the suffix from `aws sso-admin list-applications`):

```bash
# app ARN suffix = the apl-XXXX id, e.g. 722325d0aff3184d
printf 'https://portal.sso.us-east-1.amazonaws.com/saml/assertion/%s\n' \
  "$(printf '851725353202_ins-<app-ARN-suffix>' | base64)"
```

**`dex_sso_ca_data`** — the app's signing cert. **Per-application, NOT instance-wide** — do NOT reuse
`argocd_sso_ca_data` (each Identity Center SAML app has its own cert; the wrong one gives Dex
`verify signature: Could not verify certificate against trusted certs`). There's no CLI for it, so download
**this app's** metadata XML (app details → **IAM Identity Center metadata** → Download) and extract:

```bash
F="path/to/Dex (Platform SSO)_*.xml"
cert=$(xmllint --xpath 'string((//*[local-name()="X509Certificate"])[1])' "$F" | tr -d '[:space:]')
{ echo "-----BEGIN CERTIFICATE-----"; echo "$cert" | fold -w 64; echo "-----END CERTIFICATE-----"; } > signing-cert.pem
openssl x509 -in signing-cert.pem -noout -subject   # sanity: must parse (CN=amazonaws.com, OU=IDAS)
base64 < signing-cert.pem | tr -d '\n'              # -> dex_sso_ca_data
```

> **Gotcha:** the `-----END CERTIFICATE-----` marker MUST be on its own line. The naive
> `xmllint | fold | { echo; cat; echo; }` recipe glues it onto the last base64 line (no trailing newline) and
> Dex rejects it with `parse cert: trailing data`. The `echo "$cert" | fold` form above adds the newline; the
> `openssl` check catches a bad PEM before you deploy.
>
> Do NOT use the console's "Download certificate" button — it can differ from the metadata's signing cert.

Add both to `infra/live/aws/secrets.hcl` (gitignored; see `secrets.hcl.example`):

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

- `parse cert: trailing data: "...-----END CERTIFICATE-----"`: the PEM in `dex_sso_ca_data` is malformed —
  the END marker is glued to the last base64 line. Rebuild it with a newline (Step 4's `echo "$cert" | fold`
  form) and `openssl x509 ... -noout -subject` to validate before re-applying.
- `cannot create temp file: open /tmp/... read-only file system`: Dex writes its env-substituted config to
  `/tmp` at startup, so `readOnlyRootFilesystem: true` needs a writable `/tmp` emptyDir (already in the module).
- `failed to load connector`: SSO URL wrong or certificate malformed.
- `x509: certificate signed by unknown authority`: `dex_sso_ca_data` missing or incorrectly encoded.
- API-server/RBAC errors creating CRDs: confirm `rbac.createClusterScoped` is on (kubernetes storage needs it).

### Identity Center "No access" page (CloudTrail shows `Federate` → 403)

Auth succeeds but issuing the assertion is denied. CloudTrail (`aws cloudtrail lookup-events
--lookup-attributes AttributeKey=EventName,AttributeValue=Federate`) shows `Authenticate` OK then
`Federate 403 Forbidden`. Almost always **attribute mappings**, not entitlement:

- **#1 cause: the `Subject` mapping is blank** (Step 2). Fill it (`${user:email}`, format `emailAddress`).
- The user must be **assigned** to the app (a group they're in, or directly). The user also needs a **primary
  email** in Identity Center. (Note: group assignment is sufficient; a direct user assignment is equivalent.)

### Dex: `verify signature: ... Could not verify certificate against trusted certs`

`dex_sso_ca_data` is the **wrong cert** — likely reused from another app (ArgoCD) or instance-wide. The signing
cert is **per-application**. Re-extract from **this** app's metadata XML (Step 4) and re-apply.

### Backstage 500: `Authentication failed, authentication requires session support`

The oidc provider needs `auth.session.secret`. The module injects it (generated `AUTH_SESSION_SECRET` env +
an `appConfig` layer); if you see this, confirm the backstage pod has that env and the
`/app/app-config-from-configmap.yaml` `--config` arg.

### Backstage 500: `getaddrinfo ENOTFOUND sso.aws.refplat.org` (from the pod)

The backend can't resolve its own issuer hostname (public DNS / internal-NLB hairpin). The module pins it to the
in-cluster gateway via `host_aliases` (Backstage unit) → `sso.aws.refplat.org` = the `cilium-gateway-*`
ClusterIP. If the gateway Service is recreated and its ClusterIP changes, refresh that value.

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

### Logged out on every page refresh (no session persistence) — KNOWN LIMITATION

**Symptom:** after signing in, every page reload bounces back to the sign-in screen.

**Cause (architectural, not a misconfig):** the upstream IdP is Identity Center via Dex's **SAML** connector.
The SAML 2.0 protocol has no non-interactive re-query, so **Dex ignores `offline_access` and never issues a
refresh token** (<https://dexidp.io/docs/connectors/saml/>). Backstage keeps its session in memory and restores
it on reload via a silent `GET /api/auth/<provider>/refresh`, which exchanges a refresh-token cookie — and that
cookie is only set when the IdP returned a refresh token. With SAML there is none, so `/refresh` **always 401s**
and the session cannot survive a reload. This is a known Backstage gap for refresh-less providers
([backstage#15999](https://github.com/backstage/backstage/issues/15999), [#5109](https://github.com/backstage/backstage/issues/5109)).

**What does NOT fix it (verified empirically — don't re-try):**

- `offline_access` on the frontend `defaultScopes` or the backend `additionalScopes` — Dex/SAML ignores it.
- `sessionDuration` — only sets the cookie max-age; the cookie is still gated on a refresh token.
- The `SignInPage` `auto` prop — re-auth succeeds, but the next background `/refresh` 401 discards the session,
  so it re-fires → **infinite re-auth loop** (observed: `start`→`handler/frame 200`→`refresh 401`… every ~10s).
- The experimental redirect flow (`enableExperimentalRedirectFlow`) — same `/refresh` dependency → loops.

**The fix (follow-up, not yet implemented):** front Backstage with an **auth proxy** (oauth2-proxy) that does
the Dex OIDC flow once and holds its **own** durable session cookie (independent of upstream refresh tokens),
injecting `X-Auth-Request-*` identity headers. Backstage then uses `ProxiedSignInPage` + the `oauth2Proxy`
backend provider, so its `/refresh` reads the always-present headers and succeeds on every reload. Scope: a Dex
static client for the proxy, an oauth2-proxy deployment in the `backstage` namespace, repointing the
`backstage.aws.refplat.org` HTTPRoute at the proxy, and the Backstage frontend/back-end provider swap.

Until then the portal is **click-to-sign-in**: usable, but each reload requires clicking "Sign In" (the popup
completes without re-entering credentials while the Identity Center session is alive).
