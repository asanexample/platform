# ADR-087: Keycloak Admin-Plane Hardening — master-realm passkey + sealed break-glass

**Status:** Accepted (2026-06-27) — built + bound live on the platform cluster (#899/#935).

## Context

[ADR-053](053-identity-and-cross-system-authorization-strategy.md) makes Keycloak the IdP of record, and [#885](https://github.com/asanexample/platform/issues/885) added phishing-resistant passkey MFA to the **platform** workforce realm (built + bound, live). But Terraform configures Keycloak as the **master-realm `admin` user** (`admin-cli`, username + password from Secrets Manager `platform/keycloak/admin`) — a **near-superuser that bypasses all of that MFA**. It manages both realms (and itself), so it is the keys-to-the-kingdom credential.

Mitigating context (already true): the admin secret is a **32-char machine-generated, per-rebuild-rotated** `random_password`, reachable **only via the deployer role over an in-cluster port-forward** (never internet-facing, never human-typed). And crucially, `admin-cli` authenticates via the **direct-grant** flow — so MFA on the master *browser* flow does **not** stop Terraform, and **must not** (see the invariant below).

The residual risk is the **human console**: a person signing into the master-realm admin UI (`/admin/master/console`) gets full power with only a password, outside the workforce MFA. That is the bypass this ADR closes.

This was split out of #885 (kept to platform-realm workforce MFA) as [#899](https://github.com/asanexample/platform/issues/899).

## Decision

**Proportionate hardening — close the human-console bypass; leave the machine path alone.**

1. **Passkey on the master *browser* flow.** Reuse the #885 platform flow shape (`auth-cookie`/`identity-provider-redirector` ALTERNATIVE → forms: `auth-username-password-form` REQUIRED → `webauthn-authenticator-passwordless` REQUIRED) with `realm_id = "master"`, plus `webauthn-register-passwordless` as a default required action. So a human logging into the master console needs a password **and** a phishing-resistant passkey. Same **two-apply, no-lockout rollout** as #885 (`manage_master_admin` builds it; `enforce_master_browser_mfa` binds it — enroll a passkey on the master `admin` first). Opt-in, **off by default**.

2. **The master realm's `keycloak_realm` object stays UNMANAGED.** We drive policy via the flow + required-action + bindings only (these target `realm_id = "master"` directly) and rely on master's **default** WebAuthn passwordless policy (RP id defaults to the request host = the same Keycloak host). Bringing master's realm object under Terraform management would risk Terraform clobbering bootstrap-critical master settings — not worth it for a policy we can set via the flow.

3. **Seal the bootstrap admin as break-glass.** Tighten Secrets-Manager / IAM read on `platform/keycloak/admin` to the **deployer + a break-glass role only**, with **CloudTrail** audit ([ADR-037](037-cloudtrail-audit-logging.md)). Rotation is the per-rebuild `random_password` regeneration — no separate rotation machinery.

4. **INVARIANT — never disable `admin-cli` direct-grant.** It is the greenfield **bootstrap** (a from-zero rebuild configures Keycloak through it before any passkey exists) **and** the **break-glass** (an independent door when the browser flow misbehaves, ADR-068 §6). Disabling it **bricks every rebuild** and removes the recovery path. The master browser-flow hardening is additive to, never a replacement for, this path.

## On the Keycloak 26 "temporary admin" warning

Keycloak 26 flags the env-var bootstrap admin (`KC_BOOTSTRAP_ADMIN_*`) as a **temporary admin** and nags you to "create a permanent admin account and delete the temporary one." Our `admin` user (`platform/keycloak/admin`) *is* that bootstrap admin — and we **keep it on purpose; we do not follow that advice.** Recorded here so it's a decision, not a rediscovery:

- **Deleting it is the one thing we must never do** — Terraform authenticates as it (`admin-cli`), the rebuild recreates it, it's the break-glass (the INVARIANT above). The literal advice bricks us.
- **The warning's real footguns don't apply.** It targets default / shared / never-rotated admin passwords; ours is **rotated per rebuild**, **SSO + Tailscale-gated** (not internet-facing), and now has a **passkey** on its console login. The one generally-valid concern — a shared `admin` account ruins *attribution* — is **moot at single-operator scale** (it's always the same person); it only bites with a team.
- **"Create a permanent admin" is exactly the deferred full-SA migration below** — a second keys-to-the-kingdom secret + a brittle two-phase rebuild. Over-engineering for a single-operator platform.
- **When it *is* warranted (multiple human Keycloak admins), the right fix is to FEDERATE the master console to the real SSO identity** (admins log in as themselves with their normal MFA; the bootstrap admin reverts to machine-only) — **not** a second static permanent admin, which would be a worse version of the same thing. Revisit then.

## Consequences

- The master admin **console** requires a passkey; the **machine** path (`admin-cli` direct-grant) is unchanged, so Terraform, bootstrap, and break-glass are unaffected — a broken master browser flow never locks out automation (verified: binding the master flow and reverting both work cleanly against an ephemeral Keycloak 26.6.3).
- A human master-console operator must enroll a passkey first (the two-apply discipline), exactly like the platform realm.
- `teardown` is unaffected: the master resources are `keycloak_*`, so `platctl`'s `state_purge` drops them with the rest before Keycloak's DB is destroyed.

## Deferred (documented, off by default)

**Full service-account provider migration** — moving Terraform off the admin password onto a master-realm service-account client (`client_credentials`). Deferred because: the SA must be **near-superuser anyway** (it manages both realms + itself, so it's an equivalent keys-to-the-kingdom secret); the admin password + `admin-cli` direct-grant **must survive** for bootstrap + break-glass regardless; and it **adds** a second crown-jewel secret + a **brittle two-phase apply** to every teardown/rebuild — real fragility for marginal gain. Revisit if the master realm ever gets non-bootstrap automation that would benefit from scoped, auditable SA credentials.

## Related

- [ADR-053](053-identity-and-cross-system-authorization-strategy.md) (Keycloak IdP of record), [ADR-059](059-identity-topology-pluggable-idp-seam.md) (pluggable IdP seam)
- [#885](https://github.com/asanexample/platform/issues/885) (platform-realm workforce passkey MFA — the flow this reuses), [#899](https://github.com/asanexample/platform/issues/899) (this issue), the workforce identity epic [#884](https://github.com/asanexample/platform/issues/884)
- [ADR-068](068-product-scoped-and-cross-team-access-model.md) §6 (break-glass), [ADR-037](037-cloudtrail-audit-logging.md) (CloudTrail audit)
