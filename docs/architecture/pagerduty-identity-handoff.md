# PagerDuty identity handoff

How the **PagerDuty on-call structure** (provisioned in IaC by the `pagerduty` module/unit) connects to
**people** (owned by the identity & access workstream). The two workstreams meet at exactly one
interface, described below.

## The identity model

Three layers, kept deliberately separate:

1. **Account** — the person *owns* their PagerDuty account. We **link, never create** from git: no PII
   in git, and the link is "proven" because the human one-click-links it via OAuth (ADR-084).
2. **Identity link** — `person ↔ PagerDuty user-id`, held in the directory's `external_identity` table
   with `provider='pagerduty'`.
3. **Membership** — who is in which rotation. **Platform-provisioned**, *derived* from the roster
   (`gitops/people/`) + the link.

Rule of thumb: **link the people; provision the structure + membership.**

## The contract (the one interface)

The only thing the two workstreams share is the directory's `external_identity` rows where
`provider='pagerduty'` — i.e. **`person ↔ PagerDuty user-id`**.

- The **identity workstream populates** it.
- The **PagerDuty side reads** it: the membership connector (to set rotation membership) and the
  ADR-084 triage agent's on-call resolver (to page the right person).

This contract is stable: the `pagerduty` module's structure (schedules / escalation policies /
services / integrations) does not change when the link is populated — only the schedule's `users`
input is swapped from the bootstrap admin to the directory-derived roster.

## Deliverables — the identity workstream's "PagerDuty link leg"

1. **Keycloak brokers PagerDuty as an OIDC identity provider** — a one-click "connect PagerDuty" in
   the account-linking flow (ADR-084 Phase 1; currently designed, not wired).
2. **Directory sync** reads the Keycloak `FEDERATED_IDENTITY` records and upserts
   `external_identity(provider='pagerduty', tier='proven')`.
3. **Onboarding nudge** includes PagerDuty in the Keycloak first-login "connect your accounts" step /
   the Backstage people template (#890).

## On the PagerDuty side (out of scope for the identity workstream)

- The on-call **structure** — schedules, escalation policies, services, Alertmanager integrations,
  routing-key secrets — is already provisioned by the `pagerduty` module/unit (the bootstrap admin
  seeds every schedule).
- The **membership connector** (FUTURE, gated on the contract above): once
  `external_identity(pagerduty)` is populated, a connector reads `gitops/people/` (grants → who is on
  each team) joined with the directory (their PagerDuty id) and sets each team's schedule membership —
  mirroring the Keycloak/GitHub roster generators (#888/#889). It **replaces the bootstrap `users`
  input**; the structure is unchanged.
- The **triage agent's on-call paging** (ADR-084 Phase 2): consumes the `pagerduty` unit's per-team
  `escalation_policy_id` outputs to page the owning team's on-call.

## See also

- `docs/architecture/identity-and-access-strategy.md` — the decide → derive → project model and the
  connector pattern.
- `docs/adrs/084-platform-identity-directory-and-owner-resolution.md` — owner resolution + the
  link-never-create account model.
- `infra/modules/pagerduty/` — the on-call structure module (the bootstrap membership seam).
