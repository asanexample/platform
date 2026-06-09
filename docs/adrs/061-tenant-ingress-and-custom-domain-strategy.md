# ADR-061: Tenant Ingress & Custom Domain Strategy

**Date:** 2026-06-08
**Status:** Accepted — strategy/direction. Extends [ADR-060](060-tenant-app-hostname-convention.md).

## Context

[ADR-060](060-tenant-app-hostname-convention.md) made the *generated* tenant hostname
(`<app>-<team>.<base-domain>`) a single-source-of-truth value — derived from the claim and injected into the
route. That solves consistency, drift, and preview environments, but it leaves three needs open:

1. **Vanity names.** Product/marketing will not ship on `demo-alpha.preprod.aws.refplat.org`. Even within our
   own domain a team wants a cleaner label (`demo.refplat.org`).
2. **External custom domains.** In production a tenant's public URL can be *anything* — `shop.acme.com`, an apex
   `acme.com`, a domain we don't own. This is the multi-tenant custom-domain problem (Vercel / Netlify /
   Cloudflare-for-SaaS territory): per-domain DNS, certificates, ownership verification, routing, lifecycle, and
   status — at scale.
3. **Portability.** We will use a managed edge (Cloudflare for SaaS) where it earns its keep, but we must not be
   *coupled* to it. Swapping the DNS provider or the cert/edge mechanism should be a backend change, never a
   tenant-API change.

The generated name must remain the stable anchor; everything else layers on top without destabilising it.

## Decision

### 1. Hostname taxonomy — one canonical anchor, layered aliases

Three tiers, with the generated host as the **system-canonical** anchor in every one:

| Tier | Example | Zone | Cert | Domain owner |
|------|---------|------|------|--------------|
| **Generated (canonical)** | `demo-alpha.preprod.aws.refplat.org` | platform | platform wildcard | us |
| **Platform-domain alias** | `demo.refplat.org` | platform | platform | us |
| **External custom domain** | `shop.acme.com`, apex `acme.com` | managed *or* customer | per-domain | customer |

The generated host always exists and is what automation, deep-links, and **preview environments** key off.
Aliases never replace it — the app's HTTPRoute serves the **union** `[generated, ...aliases]`. "Canonical" has
two precise meanings: **system-canonical** = the generated host (stable, for tooling/previews);
**user-canonical** = an optional alias flagged `canonical: true` (the one URL for SEO; the rest 301 to it).

### 2. The claim is the sole source; `spec.domains` is intent, `status.domains` is state

`teams.hcl` hostnames are retired. The `XTenant` claim is the single source of truth, and the flat
`spec.hostnames` string list is replaced by a structured `spec.domains` (the generated canonical is implicit —
never declared):

```yaml
spec:
  domains:
    - host: demo.refplat.org           # tier-2 platform alias
    - host: shop.acme.com              # tier-3 external custom domain
      canonical: true                  # optional → user-canonical (drives redirect/SEO)
      dns: managed                     # managed (default) | external (customer-managed)
status:
  domains:
    - host: shop.acme.com
      state: DelegationRequired
      mode: platform-managed
      dnsTarget: ["ns-123.awsdns-45.org", "ns-678.awsdns-90.com"]
      reason: AwaitingNSDelegation
      message: "Delegate shop.acme.com NS to the listed nameservers."
      lastTransitionTime: "2026-06-08T00:00:00Z"
```

The Composition (allow-list), argocd-apps (route injection), and the shift-left CI all read `spec.domains` from
the claim — there is no second registry.

### 3. Two orthogonal pluggable axes behind one invariant seam

Mirroring the [ADR-059](059-identity-topology-pluggable-idp-seam.md) identity seam, the **tenant ingress
contract is invariant; the providers that fulfil it are swappable.** Two *independent* axes:

| Axis | Default | Pluggable alternatives |
|------|---------|------------------------|
| **DNS** (where the zone lives + who manages it) | **Route53, platform-managed** | Cloudflare DNS / others; per-domain `dns: external` (customer-managed) |
| **Cert / TLS termination** | **in-cluster cert-manager (DNS-01)** | edge offload (Cloudflare for SaaS / a CDN) |

Invariant across all providers: the `spec.domains` intent, the `status.domains` state machine, the Kyverno
allow-list (admits only `Active` hosts), and Host-header routing through the shared Gateway. A new provider
implements one backend behind these; the claim and every app HTTPRoute are untouched.

**Consequence — the default path is AWS-native and Cloudflare-free:** Route53 (managed zone) + cert-manager
(DNS-01) + Cilium Gateway. Cloudflare-for-SaaS is the implementation for the **customer-managed-DNS** mode
(where we cannot issue a cert ourselves) and the **scale** escape hatch — not the backbone.

### 4. DNS platform-managed by default; customer-managed is the exception

- **Platform-managed (default).** The customer delegates the domain (registrar NS → our Route53 nameservers, a
  subdomain delegation, or API credentials) **once**. After that, records + DNS-01 certs + apex (Route53 ALIAS,
  no CNAME-at-apex problem) are fully automated, with **no per-domain manual step**. The single human action —
  the NS delegation — is surfaced as `DelegationRequired` status carrying the exact nameservers.
- **Customer-managed (`dns: external`).** The customer keeps their zone; we hand them a `dnsTarget` (CNAME) + an
  ownership challenge; the cert comes via HTTP-01 / a delegated `_acme-challenge` / the edge. This is the only
  mode with a recurring per-domain manual step.

### 5. The domain lifecycle state machine (the contract everything keys off)

`status.domains[].state` — one unified machine across all tiers and modes:

| State | Meaning | Next actor |
|-------|---------|-----------|
| `Pending` | Accepted; platform provisioning backing resources (zone / custom-hostname). | platform |
| `DelegationRequired` | Platform-managed: zone ready, awaiting NS delegation. `dnsTarget` = nameserver set. | customer (one-time) |
| `VerificationRequired` | Customer-managed: awaiting ownership proof (TXT) and/or CNAME. `dnsTarget`/token provided. | customer |
| `Verifying` | Polling for the customer action to take effect (NS resolves / CNAME points / TXT present). | platform |
| `Issuing` | Verified; certificate being issued or provisioned. | platform |
| `Active` | Cert valid, route admitted by Kyverno, serving traffic. | — (steady state) |
| `Error` | Failed; `reason` + `message`; auto-retries. | platform/customer |
| `Deleting` | Removed from `spec.domains`; backing resources being torn down. | platform |

Transitions:

- Tiers 1–2 (platform-owned hosts, no customer action): `Pending → Issuing → Active`.
- Tier 3 platform-managed: `Pending → DelegationRequired → Verifying → Issuing → Active`.
- Tier 3 customer-managed: `Pending → VerificationRequired → Verifying → Issuing → Active`.
- Any non-terminal state `→ Error` on failure, and back to the appropriate state when the condition clears.
- `Active → Deleting → (removed)` on domain removal or tenant offboard.

**Enforcement coupling:** Kyverno's `restrict-route-hostnames` admits a host **only** while its status is
`Active`. Verification is therefore the security boundary — a tenant cannot route a domain it has not proven it
controls, regardless of what its HTTPRoute claims.

### 6. Automation — Crossplane per-tenant, Terragrunt substrate

- **Terragrunt (substrate, per cluster/env, applied once):** the shared Gateway + ClusterIssuer, cert-manager,
  external-dns, the Route53 account wiring, and — when the edge is enabled — the Cloudflare-for-SaaS account +
  fallback origin (`origin.<base-domain>`).
- **Crossplane Tenant Composition (per-tenant, claim-driven, GitOps):** for each `spec.domains` entry it
  provisions the backing resources for the selected provider (platform-managed: Route53 HostedZone + records +
  cert-manager `Certificate` via DNS-01; customer-managed/edge: a Cloudflare Custom Hostname) and **observes**
  their state to drive `status.domains[]`.
- **argocd-apps** injects the union of hosts into the app's HTTPRoute (extends the ADR-060 injection).

The only step outside GitOps is the customer's one-time DNS delegation / CNAME — inherent (we don't write a
zone we weren't given) and surfaced as actionable status.

**Implementation risk to spike first:** the Crossplane Cloudflare provider's coverage of the *Custom Hostname*
(SaaS) resource. If present → pure claim-driven GitOps; if not, fall back, in order, to a composition Function
calling the Cloudflare API, or a thin Terragrunt-managed module the tenant flow triggers.

## Consequences

- Single source of truth for tenant hostnames (the claim); the claim ↔ `teams.hcl` dual registry is eliminated.
- Generated names stay the automation anchor; vanity + custom domains layer on without destabilising plumbing or
  preview environments.
- The default path is AWS-native and portable — Cloudflare is one provider for one mode, isolated by the seam.
- A clear, observable lifecycle that the tenant (and Backstage, later) can act on.

**Scale caveat (documented, not yet binding):** even with managed DNS, per-domain certificates have two tails —
Let's Encrypt account-level order rate limits (fine for hundreds, tightening into the thousands) and attaching
many certs to a Cilium Gateway listener (Gateway API allows multiple cert refs for SNI, but Cilium's behaviour
at high cardinality is unproven — spike before relying on it). The edge offload is the documented lever when
either bites; the seam keeps that a backend swap, not a rewrite.

## Phased delivery

- **Phase 1 — canonical + platform-domain aliases; claim as sole source.** `spec.domains` for tiers 1–2; the
  Composition allow-list, the argocd-apps injection, and the shift-left CI all read the claim; delete `teams.hcl`
  hostnames. No new infra; ships vanity names under our domain and a clean prod story; unblocks the in-flight
  app-repo placeholder PRs the *correct* way (the shift-left becomes ADR-060/061-aware).
- **Phase 2 — external custom domains behind the seam.** The `status.domains` state machine, platform-managed
  (Route53 + DNS-01) as default, Cloudflare-for-SaaS for the customer-managed mode, the fallback origin, and
  Host-header routing.
- **Phase 3 — self-service + observability.** Backstage domain UX (add a domain, watch the state machine, get
  the delegation/CNAME target), quotas + abuse limits, apex/redirect polish.

## Delivery status & cost (2026-06)

- **Phase 1 — ✅ shipped (#264).** `spec.domains` is the sole source; the Composition allow-list, argocd-apps
  injection, and the shift-left CI all read the claim; `teams.hcl` hostnames retired.
- **Phase 2a — ✅ shipped (#266).** `status.domains` + Active-gated `restrict-route-hostnames`: a host is
  admitted only while its status entry is `Active`. The whole state machine runs **inside the Composition**
  (`function-go-templating` reads observed composed-resource status and writes the XR status) — **no separate
  controller**; proven offline in the [spike](../spikes/adr-061-phase2-ingress-spike.md).
- **Free tier — live now ($0).** Vanity hostnames **under the existing wildcard base domain**
  (`*.preprod.aws.refplat.org`) are served for free by the existing Gateway + wildcard cert + external-dns; a
  tenant declares one in `spec.domains` and 2a marks it `Active` immediately. This covers the "cleaner label"
  need at zero cost as long as the label stays under that wildcard.
- **Phase 2b (external custom domains, e.g. `shop.acme.com`) — DEFERRED for cost.** Domains we don't own can't
  reuse the wildcard cert, and on **Cilium 1.19.4** per-domain HTTPS listeners can't be added to the shared
  Gateway ([#44123](https://github.com/cilium/cilium/issues/44123) breaks the coexisting wildcard listener —
  see the spike). So 2b needs extra infra and is **not free**; it is deferred until a concrete customer domain
  exists. **Cheapest path when needed:**
  - **Cloudflare for SaaS** custom hostnames — **free for ≤100 hostnames**; custom-origin is free-tier (the
    Enterprise-only Host-header override / Origin Rules path is NOT needed — avoid it).
  - A **dedicated origin Gateway** (one catch-all HTTPS listener + a single origin cert), **isolated** from the
    shared Gateway so the Cilium multi-cert bugs can't touch live tenant ingress. Cost ≈ **one shared NLB
    (~$16/mo, flat for all custom domains)**. A free **Cloudflare Tunnel** (`cloudflared` pod) can replace the
    NLB for ~$0 recurring, trading dollars for more moving parts.
  - The Composition composes a per-domain `CustomHostname` (the Crossplane Cloudflare provider exists, Q5) and
    drives `status.domains` `Pending → VerificationRequired (CNAME + TXT) → Verifying → Active` from the
    observed `ssl.status`, using the Phase-2a status-loop pattern. The Cloudflare API token is delivered to a
    Secret-based ProviderConfig via the existing external-secrets path (`platform/cloudflare/api-token`).
  - **Routing reality:** Cloudflare keeps `Host` = the customer domain to the origin, which cannot attach to
    the shared `*.preprod…` listener (Gateway-API hostname intersection) — hence the *dedicated* catch-all
    Gateway above, **not** a new listener on the shared one.
- **Phase 2c (customer-managed DNS) / Phase 3 (Backstage UX)** — deferred with 2b.

## Relationships

- **Extends** [ADR-060](060-tenant-app-hostname-convention.md) (the generated/derived hostname).
- **Refines** [ADR-029](029-preprod-public-ingress-gateway-api.md) (public ingress) and builds on the shared
  Gateway.
- **Reuses the pluggable-seam pattern** of [ADR-059](059-identity-topology-pluggable-idp-seam.md).
- Touches the `route53`, `cloudflare/dns_delegation`, `gateway`, `external-dns`, `cert-manager`, and
  `crossplane` modules.
