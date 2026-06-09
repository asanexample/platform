# ADR-064: Backstage Provisioning Visibility & Developer Experience

**Date:** 2026-06-09
**Status:** Proposed — design-stage. The devex layer over
[ADR-062](062-self-service-tenant-provisioning.md) (self-service provisioning); minimal slice lands with the
self-service flow, the polished experience is staged behind it.

## Context

Self-service provisioning ([ADR-062](062-self-service-tenant-provisioning.md)) is only half the developer
experience — *visibility* into what happens after "submit" is the other half, and it is where the flow either
feels like a mature IDP ("watch it go Ready") or like submitting into a void. The provisioning chain spans four
systems, each with a different status source, and crucially **the Backstage scaffolder task ends at PR-open** —
stages 2–4 are asynchronous and happen *outside* it:

```text
1. Scaffolder task   → opens the PR              (Backstage built-in task log)
2. PR + CI           → envelope/diff checks, automerge   (GitHub checks)
3. ArgoCD            → syncs the merged claim     (ArgoCD Application sync/health)
4. Composition       → reconciles → Ready         (XTenant claim status conditions + status.domains)
```

So the ongoing status cannot live in the scaffolder task; it must live on the **Tenant's catalog entity page**,
where cards poll each system. The good news: we already ship the plugins for most of it (the Roadie ArgoCD
plugin and the Kubernetes plugin, both added in BACK Phase 2.4).

The goal is explicitly **a polished experience eventually** (it is what demonstrates IDP maturity), delivered
**minimal-first** so it does not gate the self-service flow.

## Decision

### 1. Minimal slice (ships with the self-service flow — mostly config)

- **Land the user on the Tenant entity page on submit** — the scaffolder `catalog:register` + `output.links`
  point at the new Tenant entity, not just the PR, so the requester immediately sees the dashboard where it
  comes alive.
- **Reuse existing plugins on that page:** the **ArgoCD** (Roadie) card for sync/health of the claim-delivery
  Application, and the **Kubernetes** plugin for the claim + composed resources (via the entity's
  `backstage.io/kubernetes-label-selector`). This is the truthful "is it actually provisioned" signal.
- The platform-projection plugin already turns claims into catalog entities; it is extended to stamp the
  annotations the cards key off.

### 2. The polished experience (staged, ADR-tracked, behind the minimal slice)

- **A custom "Tenant status" card** — the magic piece. Reads the `XTenant` claim's **status conditions**
  (`Pending → Synced → Ready`) and the `status.domains` per-domain DNS state machine (ADR-061) into one legible
  "provisioning → ready" view (the "Vercel deploy log" feel) instead of three separate plugin cards.
- **Completion notifications** — fire a "your tenant is ready" notification (the notifications backend is
  already installed) when the claim goes `Ready`, driven by an ArgoCD notification or a small claim-watch, so
  the requester need not babysit the page.
- **A provisioning timeline** — stitch submit (scaffolder) → PR/CI → sync (ArgoCD) → reconcile (Crossplane) into
  one continuous view. This is the only piece with no off-the-shelf component.
- **Richer Crossplane resource tree** — a composition/managed-resource graph (a community Crossplane Backstage
  plugin, e.g. TeraSky's) for deep debugging — polish beyond the status card.

### 3. Honest limitations (recorded, not hidden)

- There is **no single native "provisioning timeline"** without the custom card/component above — out of the
  box you get per-system cards, not one unified progress view.
- Backstage **polls** status conditions; it does not stream Crossplane events live. Adequate for a 1–2 minute
  provisioning ("refreshing status," not a live event tail).

## Consequences

- The minimal slice is near-free (config + existing plugins) and makes the self-service loop usable end-to-end.
- The polished experience is the IDP-maturity differentiator; it is captured here + as issues so the vision is
  tracked without gating delivery, and built incrementally (Tenant status card → notifications → timeline →
  Crossplane tree).
- Depends on the Tenant/Team model existing (the entity is a *Tenant*), so the visibility work follows the
  rebuild's model step even though the scaffolder *foundation* does not.

## Relationships

- **Devex layer over** [ADR-062](062-self-service-tenant-provisioning.md) (self-service provisioning).
- **Surfaces** the `XTenant` claim status of [ADR-049](049-tenant-model-team-tenant-zone.md) and the
  `status.domains` state machine of [ADR-061](061-tenant-ingress-and-custom-domain-strategy.md).
- **Reuses** the ArgoCD + Kubernetes Backstage plugins and the platform-projection plugin from
  [ADR-051](051-backstage-developer-portal.md) (BACK Phase 2.4).
- Touches the `asanexample/backstage` app (frontend cards/modules, notifications) and the platform-projection
  plugin.
