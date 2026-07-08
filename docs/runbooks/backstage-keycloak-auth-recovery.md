# Runbook: Backstage login / Keycloak workforce-user recovery

> **Purpose:** get a workforce user back into **Backstage** (and anything else fronted by the `platform`
> Keycloak realm) when their sign-in is broken — a forgotten password, a lost/stale passkey, or a wedged SSO
> session. This is the **user-account** recovery; to recover *administrative* control of Keycloak itself
> (lost admin passkey, master-realm flow broken), use
> [keycloak-break-glass.md](keycloak-break-glass.md) instead.
>
> **Scope:** Platform Engineering (needs cluster access). **Related:** ADR-053/059 (Keycloak as IdP of
> record), ADR-087 (admin-plane + passkey hardening), [keycloak-sso.md](keycloak-sso.md).

Backstage authenticates **directly** against the `platform` Keycloak realm (OIDC; Dex/oauth2-proxy retired).
So a Backstage login problem is almost always a `platform`-realm problem.

## 1. Triage the symptom

| Symptom | Cause | Go to |
| --- | --- | --- |
| Sign-in popup shows `OPError … 503 Service Unavailable` | wedged openid-client cache after a Keycloak/DB blip — **not** a password issue | [§4](#4-sso-503--not-a-password-problem) |
| Password rejected / "invalid credentials" | forgotten or stale password | [§3](#3-reset-a-users-password) |
| Password accepted, then stuck on a passkey / WebAuthn prompt | ADR-087 requires a passkey and yours is missing/stale | [§3](#3-reset-a-users-password) + the passkey note |

## 2. The mechanism — kcadm inside `keycloak-0`

The Keycloak admin secret is **pod-scoped and unreadable** by `PlatformAdmin` (and materializing it is
gated). The recovery door is to run `kcadm` **inside the `keycloak-0` pod**, authenticating with the pod's
**own** `KC_BOOTSTRAP_ADMIN_USERNAME` / `KC_BOOTSTRAP_ADMIN_PASSWORD` env — so the credential never leaves the
pod. (Prereqs: on the tailnet, `AWS_PROFILE=platform`, `--context platform`.)

```bash
# Authenticate kcadm against the master realm using the pod's sealed bootstrap admin (do this first in every
# exec below; it writes ~/.keycloak/kcadm.config inside the pod for the rest of the session).
kubectl --context platform -n keycloak exec keycloak-0 -c keycloak -- bash -c '
  /opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080 \
    --realm master --user "$KC_BOOTSTRAP_ADMIN_USERNAME" --password "$KC_BOOTSTRAP_ADMIN_PASSWORD"
'
```

> ⚠️ Use a shell var like **`JID`** for the user id — **`UID` is read-only** in bash and the assignment
> silently fails.

## 3. Reset a user's password

**Find the user** (`platform` realm):

```bash
kubectl --context platform -n keycloak exec keycloak-0 -c keycloak -- bash -c '
  /opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080 --realm master \
    --user "$KC_BOOTSTRAP_ADMIN_USERNAME" --password "$KC_BOOTSTRAP_ADMIN_PASSWORD"
  /opt/keycloak/bin/kcadm.sh get users -r platform --fields id,username,email,enabled
'
```

**Reset the password** — set `temporary=true` so the user is forced to pick their own on next login:

```bash
kubectl --context platform -n keycloak exec keycloak-0 -c keycloak -- bash -c '
  /opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080 --realm master \
    --user "$KC_BOOTSTRAP_ADMIN_USERNAME" --password "$KC_BOOTSTRAP_ADMIN_PASSWORD"
  JID=$(/opt/keycloak/bin/kcadm.sh get users -r platform -q username=<username> --fields id --format csv --noquotes)
  /opt/keycloak/bin/kcadm.sh update users/$JID/reset-password -r platform \
    -s type=password -s value="<temp-password>" -s temporary=true -n
'
```

- The realm keeps **password history** — the user cannot set a previously-used password when they change it.
  If they only need a working password now, `temporary=false` sets it directly (still subject to history).
- **Passkey note (ADR-087).** The `platform` realm can require a **passkey** on top of the password, and
  self-service "Forgot password" is off. After the reset, the user may be prompted to **enrol a new passkey**
  during login (register their device / password manager) — that's expected. If instead a **stale** passkey is
  *blocking* them, delete it (same authenticated session):

  ```bash
  # list credentials, find the webauthn / webauthn-passwordless id, then delete it
  /opt/keycloak/bin/kcadm.sh get users/$JID/credentials -r platform --fields id,type,userLabel
  /opt/keycloak/bin/kcadm.sh delete users/$JID/credentials/<credId> -r platform
  ```

## 4. SSO 503 — not a password problem

If the sign-in popup returns `OPError: expected 200 OK, got: 503`, Backstage's openid-client cached a *failed*
OIDC discovery after a `keycloak`/`keycloak-db` blip (the single-instance auth DBs are fragile). Bounce
Backstage to clear the cache — no password change needed:

```bash
kubectl --context platform -n backstage rollout restart deploy/backstage
```

If Keycloak itself is down/degraded, recover it first (check `kubectl -n keycloak get pods`; a `keycloak-db`
restart may be the root cause), then restart Backstage.

## Gotchas

- **`kcadm` writes are gated for the CLI agent in auto-mode** — a human runs the reset (or grants a one-off
  permission). The read (list users) is usually fine.
- **`UID` is read-only** — name the id var `JID` (or anything but `UID`).
- **Prereqs**: tailnet access, `AWS_PROFILE=platform`, `--context platform`; the EKS API is private (ADR-010).
- **Don't** try to read the admin secret directly — it's pod-scoped; use the in-pod bootstrap env above.

## See also

- [keycloak-break-glass.md](keycloak-break-glass.md) — recovering **admin** control (ADR-087).
- [keycloak-sso.md](keycloak-sso.md) · [keycloak-upstream-idp.md](keycloak-upstream-idp.md) — realm/federation.
- ADR-053 / ADR-059 (Keycloak IdP of record), ADR-087 (admin-plane + passkey hardening).
