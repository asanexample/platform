# ADR-096: Web Application Firewall — Edge-First via Cloudflare

**Date:** 2026-07-06

**Status:** Proposed — architecture agreed (**edge-first via Cloudflare**); **implementation deferred**
per the [ADR-092](092-platform-finops-practice.md) no-spend posture. The meaningful managed OWASP
ruleset is a **paid tier** (Cloudflare Pro, ~$20/mo/zone), so it is designed-in-but-deferred — the same
rule that defers GuardDuty ([#1178](https://github.com/asanexample/platform/issues/1178)) and commercial
DAST ([ADR-095](095-dast-dynamic-application-security-testing.md)). Realizes
[#1147](https://github.com/asanexample/platform/issues/1147); closes the "no WAF / edge protection" gap in
the [Security Model gaps register](../learn/spine/the-security-model.md) (epic
[#1152](https://github.com/asanexample/platform/issues/1152)).

## Context

Public ingress is TLS-terminated and hostname-scoped, but **nothing inspects request _content_** for
OWASP-class attacks (injection, XSS, path traversal, bad bots), and there is **no volumetric / rate-limit /
DDoS shield**. This is the thinnest part of the runtime security model at the edge. Falco
([ADR-045](045-falco-runtime-threat-detection.md)) shields the _runtime_ (syscalls); DAST
([ADR-095](095-dast-dynamic-application-security-testing.md)) _tests_ pre-prod; Kyverno
([ADR-014](014-kyverno-as-policy-engine.md)) gates _admission_. The WAF is the missing layer: an
**in-flight edge shield** for live request traffic.

Three facts constrain the design decisively:

1. **The public edge is an NLB (L4) + Cilium Gateway / Envoy** ([ADR-017](017-gateway-api-over-ingress.md) /
   [ADR-029](029-preprod-public-ingress-gateway-api.md)). **AWS WAFv2 cannot attach to an NLB** — it binds
   only to ALB, CloudFront, API Gateway, or AppSync. So AWS WAF is not a drop-in; it would force an edge
   re-architecture.
2. **The public surface is preprod, not platform.** The preprod gateway is `internal = false`
   (internet-facing); the **platform** gateway is `internal = true` (reachable only over Tailscale). The
   platform cluster therefore has effectively no public WAF need — this is preprod-first (and future-prod)
   work, mirroring the Falco rollout.
3. **Cloudflare already holds the `refplat.org` parent zone** ([ADR-022](022-dns-architecture.md)) — today
   used for DNS delegation only (NS records → Route53), explicitly _not_ proxying traffic. The edge WAF
   vehicle is therefore **already in the stack** at zero onboarding cost.

A fourth, softer constraint sets the pace: the [ADR-092](092-platform-finops-practice.md) FinOps posture is
**free OSS / free-tier native only, no spend budget** — paid tiers are designed-in-but-deferred to a future
budgeted state.

### The core principle — match the layer to the threat

"WAF" bundles jobs that have _different_ correct homes. Treating it as one box in one place is the mistake:

| Job | Correct placement | Why |
|-----|-------------------|-----|
| L3/4 + L7 volumetric DDoS, bad-bot floods | **True edge, off-cluster** (CDN) | The value is dropping junk _before_ it costs bandwidth/compute. You cannot absorb a flood at the point it is already saturating you. An in-cluster WAF has already lost this fight. |
| Coarse OWASP managed rules + global rate-limit | Edge (best), ingress (acceptable) | Cheap at the edge with a managed ruleset; workable at the gateway too. |
| Fine-grained, **app-aware** request rules (per-route, custom) | **In-cluster gateway** | Needs app/route context a generic edge WAF lacks. |

The most correct architecture is therefore **layered**: a fast edge that absorbs volume and runs managed
OWASP rules, plus an _optional_ smart in-cluster layer for app-aware rules. The edge is primary; in-cluster
is a second layer, never the primary shield.

## Decision

Adopt an **edge-first, layered WAF** with **Cloudflare** as the edge shield in front of the existing NLB —
**additive, no edge re-architecture** (the Cilium Gateway, Envoy, and Let's-Encrypt-DNS-01 TLS all stay).

### D1 — Cloudflare proxy (orange-cloud) on the public hostnames is the primary shield

Enable Cloudflare proxying for the public preprod (and future prod) app hostnames: the **Cloudflare Managed
Ruleset + OWASP Core Ruleset**, **rate-limiting rules**, and **unmetered L3/4/7 DDoS** run at Cloudflare's
edge, in front of the NLB origin.

### D2 — Origin lock (non-negotiable)

Restrict the ingress NLB security group to **Cloudflare's published IP ranges**. A WAF whose origin is
reachable directly is theater — anyone hitting the NLB IP bypasses it. This SG lock is part of the WAF, not
an afterthought.

### D3 — TLS = Full (Strict)

Edge TLS terminates at Cloudflare (Universal SSL); the **origin cert is retained** (Let's Encrypt DNS-01 via
Route53, or a Cloudflare Origin CA cert) so the Cloudflare→NLB hop is authenticated end-to-end. No
downgrade to "Flexible."

### D4 — DNS split, documented

The public app hostnames become **proxied records in the Cloudflare `refplat.org` zone**; Route53 stays
authoritative for everything else (platform-internal names, cert DNS-01, delegated subdomains). This
**revisits [ADR-022](022-dns-architecture.md)'s** "Cloudflare = DNS-only, no proxy" stance _specifically for
public app hostnames_. The tradeoff — a small split in where public-hostname DNS is managed (Cloudflare, not
external-dns/Route53) — is the price of edge protection and is scoped to public hostnames only.

### D5 — In-cluster Coraza / OWASP-CRS as an optional L2 (deferred)

A future `CiliumEnvoyConfig` injecting **Coraza** (proxy-wasm) + the OWASP Core Rule Set into the Gateway's
Envoy, for per-route / app-aware rules the edge cannot express. **Explicitly secondary and later** — it is
_not_ the primary shield: it cannot do DDoS, it sits in the critical ingress data path (a bad filter
degrades _all_ ingress), it consumes cluster compute proportional to _attack_ volume, and
proxy-wasm-on-Cilium-Envoy is the less-proven path. Kept in the design as the "layered defense" second leg,
built only if per-route custom rules are actually needed.

### D6 — Audit-first rollout

Cloudflare managed rules start in **Log** action, tune false positives against real traffic, then flip to
**Block** — the same Audit→Enforce ramp the platform uses for Kyverno and Falco (stdout-first).

### Scope

Preprod public edge, and future prod. **Platform cluster excluded** (internal / Tailscale — no public
surface). If the platform ever exposes a public endpoint, the same pattern applies to that hostname.

## Cost — and why implementation is deferred

Cash cost is the deciding factor here, by explicit direction: **we are in development, with no real external
users, no production traffic, and no real attack/DDoS surface — the protection buys nothing yet.**

| Component | Cost |
|-----------|------|
| Unmetered DDoS (L3/4/7), Universal SSL, **Cloudflare Free Managed Ruleset** (limited high-severity rules), 1 rate-limit rule, Bot Fight Mode | **$0** — Cloudflare **Free** |
| **Full Cloudflare Managed Ruleset + OWASP Core Ruleset**, tunable rate-limiting, richer bot management | **~$20/mo/zone** — Cloudflare **Pro** (**paid**) |
| AWS WAF alternative (rejected) | Per-request + WCU + a CloudFront/ALB edge — higher, per-request, AWS-locked |
| In-cluster Coraza (optional L2) | **$0** license, but cluster compute + heavy CRS false-positive tuning + data-path risk |
| Engineering (initial) | **~2–4 days** — proxied records, NLB SG lock to Cloudflare IPs, TLS Full(Strict), managed-ruleset config, log→block tuning |

**Decision on cost:** the **architecture is in force now**; **implementation is deferred** per
[ADR-092](092-platform-finops-practice.md). The full-value tier (the OWASP Core Ruleset) is **paid**
(Cloudflare Pro), and in the current dev phase there is no real-world exposure to justify either the spend or
the engineering time.

**Trigger to implement** — the first of: public **production** traffic / real external users; a regulated
(**PCI**, [ADR-013](013-compliance-tier-model.md) "WAF required on all ingress") workload; an **actual
attack / DDoS** event; or a **security budget**. Ahead of that, the **$0 free-tier floor** (unmetered DDoS +
basic managed WAF) can be switched on at the flip of the proxy toggle the moment the public edge serves
anything real — a zero-cost baseline that needs no Pro subscription.

## Consequences

### Positive

- **Puts the shield at the correct layer** — DDoS and volumetric attacks are dropped at the edge before they
  cost cluster compute, which an in-cluster WAF structurally cannot do.
- **No edge re-architecture** — additive in front of the existing NLB; the Cilium Gateway / Envoy / Gateway
  API portability ([ADR-017](017-gateway-api-over-ingress.md)) is untouched.
- **Cheapest correct option** — reuses the Cloudflare zone we already own; a real $0 floor exists, and the
  paid step is a single small subscription, not a build.
- **Consistent posture** — OSS/free-first and Audit→Enforce, matching Falco, Kyverno, and the ADR-092 FinOps
  discipline; keeps the origin (Cilium Gateway) portable so the edge CDN can be swapped later.

### Negative

- **A SaaS edge dependency** for the primary shield, and a **DNS-management split** for public hostnames
  (Cloudflare-proxied, not external-dns/Route53) — the price of edge protection (D4).
- **Value on a dev/reference platform is latent** — with no real users, this is largely _designed capability
  and demo_ until the trigger fires; deferring is the honest call, not shipping it to look complete.
- **Origin lock is a hard operational dependency** — if the NLB SG is not kept in sync with Cloudflare's IP
  ranges, the WAF is either bypassable (too open) or the site breaks (too closed).

### Risks

- **Bypass via a stale origin lock** (D2) — mitigated by automating the Cloudflare-IP-range SG and testing
  direct-to-NLB access is refused.
- **False positives blocking legitimate traffic** on the flip to Block — mitigated by the Log-first ramp
  (D6) and a per-hostname tuning pass.
- **If the optional L2 (D5) is ever built**, proxy-wasm-on-Cilium-Envoy maturity + a WAF in the critical
  data path are real reliability risks — which is exactly why it is optional and secondary.

## Alternatives considered

1. **AWS WAFv2 + CloudFront (or an ALB) at the edge.** Rejected: WAFv2 cannot bind to the NLB, so this forces
   a CloudFront distribution or an ALB in front of the Cilium NLB — abandoning the Gateway-API/Envoy edge for
   marginal gain, adding per-request cost and AWS lock-in. We already own the Cloudflare zone, so Cloudflare
   is both cheaper and already present. (Evaluated fresh; supersedes the framing in
   [ADR-029](029-preprod-public-ingress-gateway-api.md) that left the edge without a WAF.)
2. **AWS WAFv2 on the NLB directly.** Impossible — WAFv2 does not attach to an NLB.
3. **In-cluster Coraza / ModSecurity as the _primary_ WAF.** Rejected as primary (retained as the optional
   L2, D5): no DDoS capability, critical-data-path risk, compute that scales with attack volume, and the
   least-proven integration.
4. **Do nothing — rely on TLS + hostname scoping.** Rejected: that _is_ the named gap — no content
   inspection and no DDoS shield at all.

## Relationships

- **Realizes** [#1147](https://github.com/asanexample/platform/issues/1147); under the security posture epic
  [#1152](https://github.com/asanexample/platform/issues/1152); closes the "no WAF / edge protection" gap in
  the [Security Model gaps register](../learn/spine/the-security-model.md).
- **Sits in front of** the [ADR-017](017-gateway-api-over-ingress.md) Gateway /
  [ADR-029](029-preprod-public-ingress-gateway-api.md) public ingress; **revisits**
  [ADR-022](022-dns-architecture.md)'s Cloudflare-DNS-only stance for public app hostnames.
- **Deferred per** [ADR-092](092-platform-finops-practice.md) FinOps — the same rule that defers GuardDuty
  ([#1178](https://github.com/asanexample/platform/issues/1178)).
- **Defense-in-depth siblings:** Falco ([ADR-045](045-falco-runtime-threat-detection.md), runtime), DAST
  ([ADR-095](095-dast-dynamic-application-security-testing.md), pre-prod test), Kyverno
  ([ADR-014](014-kyverno-as-policy-engine.md), admission). **Compliance forcing function:**
  [ADR-013](013-compliance-tier-model.md) (WAF required on all ingress at the PCI tier).
