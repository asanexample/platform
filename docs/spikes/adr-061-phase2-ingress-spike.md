# Spike: ADR-061 Phase 2 ingress — de-risking findings

**Date:** 2026-06-08
**Status:** Complete. Informs the Phase 2 build plan (no production code shipped by this spike).
**Relates to:** [ADR-061](../adrs/061-tenant-ingress-and-custom-domain-strategy.md), builds on Phase 1 (PR #264).

## Why

ADR-061 Phase 2 adds the `status.domains` state machine, **Active-gated** Kyverno enforcement, and external
custom domains (per-domain DNS-01 cert + Gateway ingress). It rested on a few unproven assumptions. This spike
resolves each with an explicit verdict + evidence so the 2a/2b plan carries no hidden architectural risk.

## Verdicts at a glance

| # | Unknown | Verdict |
|---|---------|---------|
| Q1 | State machine + Active-gating inside the Composition (no controller) | ✅ **Proven** |
| Q2 | Per-domain TLS on the shared Cilium Gateway | ⛔ **High-risk — avoid; prefer edge offload** (one live test left) |
| Q3 | Crossplane Route53 coverage (zone + nameservers + records) | ✅ **Proven** (one-word provider add) |
| Q4 | cert-manager / external-dns multi-zone | ✅ **Proven** (small additive IRSA delta) |
| Q5 | Crossplane Cloudflare `CustomHostname` (SSL-for-SaaS) | ✅ **Proven — exists** (resolves the ADR's flagged risk) |

---

## Q1 — Composition-driven state machine (the linchpin) — ✅ PROVEN

**Claim under test:** earlier exploration concluded Phase 2 needs a *separate controller* because "the
Composition can't read status." **This is wrong.** `function-go-templating` (v0.12.1, installed) can read an
**observed composed resource's status** *and* write the **composite's own status** — so the whole state
machine lives in the Composition. Cert issuance *is* the verification signal; no new controller.

**Evidence** — a throwaway Composition (`/tmp/p2spike`, uncommitted) that, per `spec.domains` entry: treats
the generated host + tier-1/2 aliases as `Active` unconditionally, gates tier-3 external hosts on an observed
cert-manager `Certificate` Ready condition, writes `status.domains[]`, and builds the
`restrict-route-hostnames` allow-list = `{generated, tier-1/2} ∪ {tier-3 Active}`. Run with
`crossplane render … --observed-resources <dir>` across three fixtures:

| Fixture | tier-3 `shop.acme.com` state | allow-list |
|---------|------------------------------|-----------|
| cert `Ready=True` | `Active` (CertIssued) | `[demo-alpha (generated), shop.acme.com, vanity]` |
| cert `Ready=False` | `Issuing` (AwaitingCert) | `[demo-alpha, vanity]` |
| cert **absent** (first reconcile) | `Issuing` | `[demo-alpha, vanity]` |

All three pass criteria hold: (i) `status.domains` reflects each fixture; (ii) the **generated host is in the
allow-list in every case** (no-regression — live alpha/bravo never stranded); (iii) the tier-3 host is
admitted **only** once its cert is Ready.

**Two mechanics worth recording for the build:**

- **Read observed composed status:** `index $observed "<composition-resource-name>"` then
  `.resource.status.conditions`. **Gotcha:** inside `{{ range }}`, Go rebinds `.` to the element — capture
  `{{- $observed := .observed.resources | default dict }}` *before* the loop, or `.observed` is nil inside it.
- **Write composite status:** emit an object with the **XR's apiVersion+kind and NO
  `gotemplating.fn.crossplane.io/composition-resource-name` annotation**. With the annotation it is treated as
  a *composed* nested XEnvironment (shows up as an unready resource) instead of merging into the composite status.

**Consequence:** the Phase 2 status loop + enforcement coupling is a **Composition-only** change
(go-template + XRD status schema). No controller, no new function. This is the strongest possible result and
makes 2a low-risk.

---

## Q2 — Per-domain TLS on the shared Cilium Gateway — ⛔ HIGH-RISK, AVOID

We run **Cilium 1.19.4** (`infra/live/aws/_versions.hcl:79`) with one **wildcard** HTTPS listener
`*.preprod.aws.refplat.org` + a single wildcard cert (`infra/modules/gateway/main.tf:72-88`). cert→
`cilium-secrets` sync is **automatic** (Cilium copies a Gateway-referenced TLS secret to `cilium-secrets`;
no module code needed). Tier-1/2 aliases under the wildcard therefore need **zero** Gateway/cert change.

**Tier-3 external domains do NOT match the wildcard**, so the naive approach is to add a per-domain HTTPS
listener (or multiple cert refs) to the shared Gateway. **Open Cilium bugs make this unsafe:**

- **[cilium #44123](https://github.com/cilium/cilium/issues/44123)** — adding specific-hostname HTTPS
  listeners to a Gateway that **also has a wildcard listener breaks the wildcard listener entirely** (its
  `CiliumEnvoyConfig` stops generating). This is *exactly* our shared Gateway → risk of taking down **all**
  environment ingress.
- **[cilium #41228](https://github.com/cilium/cilium/issues/41228)** — multiple `certificateRefs` on a single
  listener → Envoy config fails ("duplicate matcher"). Rules out single-listener-multi-cert SNI.
- **[cilium #40966](https://github.com/cilium/cilium/issues/40966)** — Envoy doesn't fall back to a default
  cert when SNI is absent.

**Verdict: do not add per-domain listeners to the shared Gateway.** Two viable paths for tier-3:

1. **Edge offload (recommended)** — terminate the custom domain's TLS at **Cloudflare for SaaS** (Q5 confirms
   the provider), origin = the environment's wildcard host (`<app>-<team>.<base>`). The shared Cilium Gateway is
   untouched; Cilium's multi-cert limitations are sidestepped entirely. This is the ADR's documented edge lever
   — Q2 makes it the *default* for tier-3, not just the customer-managed fallback.
2. **Isolated separate Gateway** per custom domain (own NLB) — avoids #44123 (wildcard untouched) but costs an
   NLB each and still leans on Cilium multi-listener behavior; only if edge offload is undesirable.

**One live test left (cheap, do before committing 2b):** on an **isolated throwaway** Gateway (never the live
`preprod-gateway`), reproduce #44123 on 1.19.4 — wildcard + one specific HTTPS listener — to confirm the
in-cluster path is truly out. If #44123 does *not* reproduce on 1.19.4, path 2 reopens.

---

## Q3 — Crossplane Route53 coverage — ✅ PROVEN

`provider_services = ["ecr","iam","eks"]` today (`infra/live/aws/preprod/.../crossplane/terragrunt.hcl:80`);
adding `route53` is a one-word change (Upbound provider-family-aws → `provider-aws-route53`). The Route53
`Zone` managed resource exposes its authoritative nameservers in **`status` (`…delegationSet/atProvider
.nameServers`)** — exactly the `status.domains[].dnsTarget` for the `DelegationRequired` state — and `Record`/
`ResourceRecordSet` covers records. For a **platform-managed external** domain, **cert issuance is itself the
delegation proof**: Let's Encrypt only resolves the `_acme-challenge` TXT in our zone once the customer has
delegated NS to us → `cert Ready ⇒ Active`, no separate verification poller. Apex domains use a Route53
**ALIAS** at apex → NLB (no CNAME-at-apex problem). Sources:
[HostedZone CRD](https://marketplace.upbound.io/providers/crossplane-contrib/provider-aws/v0.42.0/resources/route53.aws.crossplane.io/HostedZone/v1alpha1),
[ResourceRecordSet CRD](https://marketplace.upbound.io/providers/crossplane-contrib/provider-aws/v0.44.2/resources/route53.aws.crossplane.io/ResourceRecordSet/v1alpha1).

## Q4 — cert-manager / external-dns multi-zone — ✅ PROVEN (small delta)

Both IRSA policies are **single-zone** today:

- cert-manager: `resources = [var.route53_hosted_zone_arn]` (`infra/modules/cert-manager/main.tf:99`).
- external-dns: `resources = [var.route53_hosted_zone_arn]` + `domain_filters = ["preprod.aws.refplat.org"]`
  (`infra/modules/external-dns/main.tf:82`, live `terragrunt.hcl:72`).

Multi-zone is a **small additive change**: widen both policies to a **list** of zone ARNs (or
`arn:aws:route53:::hostedzone/*`, acceptable since custom zones live in the preprod account) and add the new
zones to external-dns `domainFilters`. No structural rework. (Only needed for the *in-cluster* tier-3 path; the
edge-offload path issues the cert at Cloudflare and may not need cert-manager at all for those domains.)

## Q5 — Crossplane Cloudflare `CustomHostname` — ✅ PROVEN (resolves ADR risk)

ADR-061 flagged "spike first: does the Crossplane Cloudflare provider cover the Custom Hostname (SaaS)
resource?" **It does.** Both
[crossplane-contrib/provider-cloudflare](https://github.com/crossplane-contrib/provider-cloudflare) and the
upjet-based [provider-upjet-cloudflare](https://marketplace.upbound.io/providers/wildbitca/provider-upjet-cloudflare/v0.1.1)
expose **`CustomHostname`** + **`FallbackOrigin`** (SSL-for-SaaS on a Zone). So the customer-managed / edge
path is **claim-driven GitOps** — no fallback to a composition Function or Terragrunt module. Combined with Q2,
this makes edge offload the pragmatic primary for tier-3 external domains.

---

## Recommended Phase 2 decomposition

**2a — status.domains state machine + Active-gating (next; low-risk, ~Phase-1-sized, NO new infra).**

- Add `status.domains[]` to the `XEnvironment` XRD (host, state, mode, dnsTarget, reason, message, lastTransitionTime).
- Composition (Q1 pattern): write `status.domains`; generated + tier-1/2 → `Active` immediately; tier-3 entries
  → `Pending` (no backing resources yet); build the allow-list = `{generated, tier-1/2} ∪ {Active}`.
- ArgoCD `XEnvironment` `ignoreDifferences`: add `.status` so selfHeal doesn't fight Crossplane's status writes
  (`infra/live/aws/platform/.../argocd/terragrunt.hcl`).
- Ships the security-boundary architecture + domain observability with no infra risk.

**2b — tier-3 external domains.** Add `provider-aws-route53`; Composition composes the `Zone` (surface
`status…nameServers` → `dnsTarget`/`DelegationRequired`) and drives the state machine. **Ingress edge decision
(the crux, from Q2): default to Cloudflare-for-SaaS edge termination** (origin = the environment's wildcard host)
rather than per-domain Cilium listeners; gate the in-cluster alternative on the one remaining live #44123 test.
Multi-zone cert-manager/external-dns IRSA only if the in-cluster path is chosen.

**2c — customer-managed DNS.** Folds into 2b's edge path using the confirmed Cloudflare `CustomHostname` +
`FallbackOrigin`; differs mainly in the ownership challenge (TXT/CNAME) surfaced via `status.domains` states
`VerificationRequired`/`Verifying`.

## Open follow-up

- **Live test:** reproduce [cilium #44123](https://github.com/cilium/cilium/issues/44123) on 1.19.4 with an
  isolated throwaway Gateway before committing 2b's ingress path. If it does not reproduce, the
  separate/in-cluster path reopens as an alternative to edge offload.
- Shift-left (`kyverno-validate`) stays **spec-driven** (cluster-free) — it cannot read live `status.domains`;
  it validates intent, admission enforces `Active`. Document this in 2a.
