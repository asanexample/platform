# Troubleshooting: SSO / "I can't log in"

Start here when someone can't sign into **ArgoCD** or **Backstage**, or logs in but has **no permissions**. For
how the system fits together, read [identity-and-sso](../architecture/identity-and-sso.md) first.

**Who's the IdP (as of 2026-06):** **Keycloak** (`https://keycloak.aws.refplat.org/realms/platform`). Both
ArgoCD and Backstage authenticate against it **directly over OIDC**. (Dex and oauth2-proxy were retired — if a
symptom points at `sso.aws.refplat.org` or an oauth2-proxy pod, it's stale.)

## Triage by symptom

| Symptom | Most likely cause | Jump to |
|---------|-------------------|---------|
| Logs in fine but **sees nothing / "no permissions"** | Not in a Keycloak group (the membership gap) | [§1](#1-logged-in-but-no-access) |
| **Redirect loop** / "invalid redirect_uri" | Client redirect URI / issuer URL mismatch | [§2](#2-redirect-loop--invalid-redirect_uri) |
| **TLS / cert error** reaching Keycloak | Gateway cert / split-horizon host-alias | [§3](#3-tls-or-cert-errors) |
| **500 / "failed to query provider"** | Client secret not synced, or Keycloak down | [§4](#4-500--provider-errors) |
| Backstage: **logged out on every refresh** | OIDC refresh not working (Keycloak refresh token) | [§5](#5-backstage-session-drops-on-refresh) |
| **CLI** (`argocd login`) fails | Public `argocd-cli` client / PKCE | [§6](#6-argocd-cli-login) |

## 1. Logged in but no access

The user authenticated, but their token carried **no (or the wrong) `groups`** — so default-deny RBAC gives
them nothing. This is the **most common** issue.

```bash
# What groups did Keycloak actually put in the token?
# ArgoCD UI → User Info shows the groups claim. Or decode the id_token (jwt.io) and look at "groups".
```

- **Standalone mode (today):** the user isn't in a Keycloak group. Fix in the **Keycloak admin UI**
  (`keycloak.aws.refplat.org`, admin creds at Secrets Manager `platform/keycloak/admin`): Users → the user →
  Groups → Join → `alpha` / `platform-admins` / etc. Seed users (`admin`, `dev-alpha`, `dev-bravo`) are
  pre-placed; a brand-new user is in **no** group until you add them.
- **Federated, group-emitting upstream (Okta/Entra):** the upstream group name must match the team's
  `ssoGroup` in `_teams.hcl`, and the advanced-group mapper must exist. Verify the upstream actually emits the
  `groups` claim and that `keycloak-config` ran after the team was added.
- **Federated AWS Identity Center:** IdC emits **no groups** — membership must be assigned manually in Keycloak
  (the documented gap). Same fix as standalone.
- **ArgoCD specifically:** confirm the group→role line exists — RBAC is generated from `_teams.hcl`
  (`g, <team>, role:team-<team>`; `g, platform-admins, role:org-admin`). A team added to `_teams.hcl` needs the
  `argocd` unit re-applied to pick up the new RBAC row.

## 2. Redirect loop / invalid redirect_uri

The OIDC client's registered redirect URI or the issuer URL doesn't match what the app sends.

- ArgoCD's issuer must be `https://keycloak.aws.refplat.org/realms/platform` and its `url` must be
  `https://argocd.aws.refplat.org`. Check the `argocd` unit + the `argocd` client in Keycloak (Clients →
  argocd → Valid redirect URIs include `https://argocd.aws.refplat.org/auth/callback`).
- Backstage's issuer is the same realm; its `backstage` Keycloak client redirect URI is
  `https://backstage.aws.refplat.org/api/auth/oidc/handler/frame`.
- After changing clients, re-apply `keycloak-config`.

## 3. TLS or cert errors

In-cluster components reach Keycloak's **public** hostname but over an in-cluster path (split-horizon): the
`backstage` unit adds a **host-alias** mapping the issuer host (`keycloak.aws.refplat.org`) to the Cilium
gateway ClusterIP. If that Service was recreated, the pinned IP is stale.

```bash
kubectl -n default get svc cilium-gateway-platform-gateway -o jsonpath='{.spec.clusterIP}'
# Compare to host_aliases[].ip in the backstage unit; update + re-apply if changed.
kubectl -n keycloak get certificate,httproute   # gateway TLS for keycloak.aws.refplat.org healthy?
```

The wildcard cert (`*.aws.refplat.org`) is issued by cert-manager — see
[debug-ingress-and-dns](debug-ingress-and-dns.md) if the cert itself is the problem.

## 4. 500 / provider errors

- **Client secret missing:** confidential clients read their secret from an ExternalSecret synced from
  Secrets Manager (`platform/keycloak/<client>-oidc`). Check the ExternalSecret is `SecretSynced`:
  `kubectl -n argocd get externalsecret`.
- **Keycloak down / DB:** `kubectl -n keycloak get pods` (Keycloak + its CloudNativePG cluster). A pending DB →
  Keycloak won't start. See the keycloak module README.

## 5. Backstage session drops on refresh

This was the original #202 problem (SAML/Dex had no refresh token; an oauth2-proxy worked around it). It is now
solved at the root: Backstage uses direct Keycloak OIDC, and Keycloak issues refresh tokens. If it recurs:

- Confirm the `backstage` Keycloak client has **Standard Flow** enabled and issues a refresh token (it does by
  default; keycloak-config creates it with `standard_flow_enabled = true`).
- Check the Backstage backend log for the silent refresh: `kubectl -n backstage logs deploy/backstage | grep -i
  'oidc\|refresh'`. A 401 on `/api/auth/oidc/refresh` means the IdP didn't return a refresh token.
- Confirm Backstage is using the **`oidc`** sign-in provider (app-config.production.yaml), and the Keycloak
  **SSO Session Idle/Max** timeouts aren't shorter than expected.

## 6. ArgoCD CLI login

`argocd login` uses the **public** `argocd-cli` Keycloak client (PKCE, no secret). If it fails: confirm the
`argocd-cli` public client exists in Keycloak and its redirect URI allows the CLI's localhost callback. The
browser SSO and the CLI are **different clients** — one working doesn't prove the other.

## Escalation

- App-specific setup: [argocd-sso](argocd-sso.md) (legacy/Keycloak), [keycloak-sso](keycloak-sso.md),
  [keycloak-upstream-idp](keycloak-upstream-idp.md), [dex-sso](dex-sso.md) (legacy).
- Architecture + the access model: [identity-and-sso](../architecture/identity-and-sso.md).
