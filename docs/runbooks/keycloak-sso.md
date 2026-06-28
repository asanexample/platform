# Keycloak SSO — Identity Center SAML broker setup

> **OPTIONAL — federation only.** By default Keycloak is the **IdP of record** (ADR-053/059): identity lives in
> the `platform` realm and nothing brokers up, so this setup is **not** required. Follow it only when you choose
> to federate to AWS Identity Center (set `upstream` in the `keycloak-config` unit). For Okta/Entra/Google
> presets see [keycloak-upstream-idp.md](keycloak-upstream-idp.md).

How to wire Keycloak's `aws-sso` SAML identity-provider broker (ADR-053, B2) to AWS Identity Center, so
Keycloak federates authentication **up** to AWS SSO. Keycloak gets its **own** Identity Center SAML application,
hence its own signing certificate.

The broker itself is created as code by the `keycloak-config` unit (`keycloak_saml_identity_provider`). This
runbook covers the **one-time manual Identity Center app** + the two secrets it produces.

## 1. Create the Identity Center SAML application

In the AWS Identity Center console → Applications → Add application → **custom SAML 2.0**:

- **Display name:** `Keycloak (Platform SSO)`
- **Application ACS URL:** `https://keycloak.aws.refplat.org/realms/platform/broker/aws-sso/endpoint`
- **Application SAML audience:** `https://keycloak.aws.refplat.org/realms/platform`
  (must equal the broker's `entity_id` — the realm URL the module derives)

> The realm is `platform`; the broker alias is `aws-sso`. If you change `realm_name`/`upstream.alias` in the
> `keycloak-config` inputs, update both URLs above. (For non-SAML upstreams — Okta/Entra/Google — see
> [keycloak-upstream-idp.md](keycloak-upstream-idp.md).)

## 2. Attribute mappings (console-only)

| User attribute | Maps to | Format |
| -------------- | ------- | ------ |
| Subject | `${user:email}` | emailAddress |
| email | `${user:email}` | unspecified |

The broker uses the NameID (Subject) as the principal (`principal_type = SUBJECT`, `name_id_policy_format =
Email`) and imports the `email` attribute. Do **not** add a groups mapping — Identity Center can't emit groups
over SAML (the named group claims come from Keycloak itself once the access-model-as-code taxonomy lands).

## 3. Extract the two secrets → `secrets.enc.yaml`

From the application's IdP metadata:

- **`keycloak_sso_url`** — the IdP SSO (SAML assertion) URL, e.g.
  `https://portal.sso.us-east-1.amazonaws.com/saml/assertion/<id>`.
- **`keycloak_sso_ca_data`** — the IdP **signing certificate as the BARE base64 cert body** (the
  `<X509Certificate>` content from the metadata): the base64 between the PEM `-----BEGIN/END CERTIFICATE-----`
  markers, on a single line, **with no headers or newlines**.

  ⚠️ Keycloak's `signing_certificate` wants the raw cert body, **not** base64-of-PEM. From a PEM file:

  ```bash
  # bare base64 DER body, single line
  openssl x509 -in keycloak-idp.pem -outform DER | base64 | tr -d '\n'
  # (or, if you have the metadata XML, copy the <ds:X509Certificate> text verbatim — already in this form)
  ```

Add both to the committed SOPS store `infra/live/aws/secrets.enc.yaml` (ADR-066), via
`sops infra/live/aws/secrets.enc.yaml` (decrypts at the management `platform-sops` KMS key):

```yaml
keycloak_sso_url: "https://portal.sso.us-east-1.amazonaws.com/saml/assertion/<id>"
keycloak_sso_ca_data: "MIID...single-line-no-headers..."
```

(The gitignored plaintext `secrets.hcl` is only the `TG_SOPS_BOOTSTRAP` from-zero escape, before the KMS key exists.)

## 4. Apply + verify

`keycloak-config` applies over an in-cluster **port-forward** to `http://localhost:18080` — its `start_pf` hook
runs `scripts/kc-portforward.sh`, so the provider talks to Keycloak through the forwarded port, **not** the tailnet
hostname (Keycloak must be serving). Tailscale is only needed for the **browser verify** step below. Verify the
broker **without any app client** via the account console:

```text
https://keycloak.aws.refplat.org/realms/platform/account
```

→ "Sign in" should redirect to AWS Identity Center; after authenticating, a Keycloak user is created from the
SAML email.

## Gotchas

- **Cert format** is the #1 failure mode — a base64-of-PEM value makes Keycloak reject the IdP
  signature silently. Use the bare body.
- **Audience mismatch** — the IdC SAML audience must exactly equal `https://keycloak.aws.refplat.org/realms/platform`.
