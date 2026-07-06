# ADR-095: Dynamic Application Security Testing (DAST)

**Date:** 2026-07-06

**Status:** Proposed — direction agreed, **queued behind the Falco / east-west-mTLS / WAF security
push**. Closes the design for the "no DAST" **Code**-layer gap named in the
[Security Model gaps register](../learn/spine/the-security-model.md) and tracked under the security
posture epic ([#1152](https://github.com/asanexample/platform/issues/1152)). OSS-only; **near-zero
cash cost, engineering-time cost is the real cost.**

## Context

The platform's application-layer security is **shift-left and static**: SAST, SCA, secret-scanning
(gitleaks, shipped), signed + digest-pinned images, and Kyverno admission control. What it does **not**
do is exercise the **running** application — no **DAST** (Dynamic Application Security Testing) probes a
live deployment for OWASP-class defects (injection, broken auth, XSS, SSRF, misconfigured headers,
exposed endpoints). The security-model doc names this honestly: *"No DAST; app-layer (OWASP) runtime
defense thin — running-app vulnerabilities aren't actively tested or shielded."* Its sibling gap, a
**WAF** at the edge ([#1147](https://github.com/asanexample/platform/issues/1147)), is the *runtime
shield*; DAST is the *pre-prod test*. They are complementary and both open.

DAST needs a **running target**, which is exactly what this platform already produces in a governed
way, so the capability slots onto existing seams rather than introducing new infrastructure:

- Apps deploy to environment namespaces reachable over **HTTPRoute** — the promotion-ladder lower
  stages (`dev`/`test`/`staging`, #377) and the **PR preview** hostnames ([ADR-032](032-pr-preview-environments.md)).
- CI runs on the **self-hosted ARC runners** ([ADR-065](065-self-hosted-github-actions-runners-arc.md)).
- App CI is already a **thin caller of shared `trusted-ci` reusable workflows** (the
  [ADR-050](050-shared-build-sign-reusable-workflow.md) build-sign model).
- **SARIF** is already ingested into GitHub code scanning (SAST/SCA land there today).

The constraint that shapes the tooling choice: the platform FinOps posture
([ADR-092](092-platform-finops-practice.md)) is **free OSS/native only, no spend budget** — paid tiers
are documented-but-deferred (the same rule that defers GuardDuty, #1178).

## Decision

Adopt an **OSS DAST capability delivered as a shared `trusted-ci` reusable workflow**, run from the
existing ARC runners against already-deployed lower-stage / preview targets, **audit-first** then
gating on high-severity, with results as **SARIF** into GitHub code scanning.

### 1. Tooling — OSS

- **OWASP ZAP** as the primary scanner: `zap-baseline` (passive spider — fast, low-FP, per-PR) and
  `zap-full-scan` (active payloads — slow, scheduled), plus the API scan for OpenAPI/GraphQL targets.
  First-class GitHub Action, auth contexts, SARIF output.
- **Nuclei** (ProjectDiscovery) as a complementary template scanner for known-CVE / misconfig /
  exposure checks — fast, high-signal, covers ground ZAP's generic crawler does not.
- **Not** StackHawk / Burp Enterprise (better DX + managed FP triage, but paid) — documented-but-
  deferred per ADR-092, revisited only with a security budget or a compliance driver.

### 2. Delivery — a shared reusable workflow (the build-sign pattern)

A platform-owned **`trusted-ci/dast.yml`** reusable workflow. An app opts in with a thin caller (like
build-sign): after its deploy to a preview/test URL, the workflow runs the baseline scan against the
live target; a scheduled job runs the full active scan against `staging`. The scan logic, ZAP
automation config, and severity policy are **platform-owned**; the app only supplies its target URL and
(optionally) an auth profile.

### 3. Authenticated scanning — the hard part, designed in

An unauthenticated scan only sees the public surface. ZAP's **auth context points at a Keycloak test
user** (the realm seed-users already exist) to scan past login. This is where DAST programs spend their
effort; it is called out explicitly so it is scoped, not discovered late.

### 4. Gating — audit-first, mirroring the Kyverno philosophy

Non-blocking (report-only) first, then flip to **block-on-high-severity** once each app's baseline is
tuned — the same audit→enforce ramp the platform uses for policy. A **per-app baseline/allowlist**
suppresses known false positives (DAST is inherently noisy).

### 5. Results routing

SARIF → the GitHub Security tab (alongside SAST/SCA); high-severity findings route through the existing
owner-resolution / observability path ([ADR-084](084-platform-identity-directory-and-owner-resolution.md)).

### 6. The parking tension — an explicit design constraint

DAST needs a live target, but the clusters **park overnight** to save cost. So the *nightly full scan*
conflicts with parking. Resolution: scan existing preview/`staging` during **unparked business hours**,
or spin an **ephemeral target** for the scan window (the ADR-032 preview mechanism) — do **not** stand
up an always-on staging just to scan it (that reintroduces the cost parking removes).

## Cost

**Cash cost is near-zero; the cost is engineering time and false-positive maintenance.**

| Component | Cost |
|-----------|------|
| Tooling (ZAP + Nuclei) | **$0** — OSS |
| Compute | **Low** — baseline ≈ a few runner-minutes/PR; full nightly ≈ 30 min–few hrs of runner time on existing ARC runners. Marginal EC2 = a bounded scan-window Karpenter node → order of **$0–low tens/month** |
| Scan target | **$0** if scanning existing preview/`staging` in unparked hours; an always-on staging would be the real cost (rejected — see §6) |
| Engineering (initial) | **~1–2 weeks** — the reusable workflow, ZAP automation config, Keycloak auth context, SARIF wiring, initial FP baseline |
| Engineering (ongoing) | Per-app onboarding + **FP triage** — the durable cost of any DAST program |
| Commercial alternative (StackHawk) | ~per-app/month or seat-based — **deferred** (ADR-092) |

## Consequences

### Positive

- **Closes the Code-layer runtime-testing gap** with zero new Tier-0 infra — reuses ARC, the
  trusted-ci pattern, preview environments, Keycloak seed users, and SARIF ingestion.
- **Complements the WAF** (#1147): DAST tests pre-prod, WAF shields in-prod — the two OWASP-runtime
  gaps close from both directions.
- **Audit-first** keeps it from blocking delivery while baselines are noisy, then hardens to a real
  gate — the platform's proven policy-rollout ramp.
- **OSS-only** keeps the free/native FinOps posture intact.

### Negative / honest limits

- **Value on demo apps is moderate.** alpha/shop-class apps have a thin real vuln surface; on this
  **reference platform** DAST is substantially about *demonstrating the capability* (dogfooding the
  paved road) rather than finding real bugs. Legitimate and on-mission, but not oversold.
- **Authenticated scanning + FP tuning are ongoing toil** — the real recurring cost, not the setup.
- **Parking tension** constrains *when* full scans run (§6).
- **Not a substitute** for the WAF, pentest/red-team ([#1151](https://github.com/asanexample/platform/issues/1151)),
  or a block-on-critical-CVE gate — it is one leg of the Code-layer story.

### Sequencing

Explicitly **after** the current security push (Falco [ADR-045](045-falco-runtime-threat-detection.md)/#149,
east-west mTLS [ADR-057](057-service-identity-and-east-west-zero-trust.md), WAF #1147) — those close
higher-severity *detection* and *edge* gaps; DAST is lower real-bug ROI and is queued behind them.

## Relationships

- **Closes** the "no DAST" gap in the [Security Model gaps register](../learn/spine/the-security-model.md);
  tracked under epic [#1152](https://github.com/asanexample/platform/issues/1152).
- **Delivery pattern** from [ADR-050](050-shared-build-sign-reusable-workflow.md) (shared reusable
  workflow) on [ADR-065](065-self-hosted-github-actions-runners-arc.md) runners.
- **Target** is the [ADR-032](032-pr-preview-environments.md) preview environments / the #377 promotion
  ladder's lower stages.
- **Complements** the WAF ([#1147](https://github.com/asanexample/platform/issues/1147)); **feeds**
  compliance evidence ([ADR-055](055-compliance-assurance-and-continuous-control-evidence.md)).
- **Same FinOps discipline** ([ADR-092](092-platform-finops-practice.md)) that defers GuardDuty
  (#1178) and commercial DAST.
