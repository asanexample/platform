# ADR-089: Governance Registry Topology — one git source, projected per-cluster

**Date:** 2026-06-29

**Status:** Proposed (design — 2026-06-29)

## Context

The platform's governance/identity registries are git-native single sources (ADR-061/063/067):

- **Team** (`gitops/teams`) — ownership + the envelope a team may author within, plus governance metadata
  (SSO group, release-approvers, the team's Slack channel / PagerDuty for incident routing).
- **WorkforceRole** (`gitops/roles`, #887) — the role catalog: each role's power, risk tier, AWS permission set,
  and borrow-duration cap.
- **Person** (`gitops/people`, ADR-084) — the workforce roster: who holds/may-borrow which role at which reach
  (access facts only, no PII).

These are authored in git, but they are **consumed at runtime by in-cluster controllers**, and that is where the
topology question bites. Today only **Team** is projected to a cluster, and only to the **preprod workload
cluster** — because that is where Kyverno admits tenant `XEnvironment` claims and must read the team envelope
locally and synchronously (ADR-063). WorkforceRole and Person are not projected anywhere yet.

Two forces now make "which cluster does the registry live on?" a question with no single answer:

1. **Control-plane readers live on the hub.** The ADR-088 activation operator reads Person + WorkforceRole (and
   Team, to know which channel to *loudly announce* a break-glass activation to); the ADR-084 triage agent
   resolves Team→Slack for owner-routing; Backstage projects Team→catalog. All run on the **hub**.
2. **The platform team is itself a governed team.** Per ADR-067 the platform team is a first-class team that
   deploys its **own** workloads — many of them **on the hub**. So the hub runs governed workloads and needs the
   registry for **its own admission**, exactly like preprod does for tenants.

So the registry has readers in multiple places at once, and the set grows as prod clusters come online and as the
platform team deploys more of its own services. A single-home model cannot serve them.

## Decision

**D1 — One git source, projected (read-only) to every cluster that reads it.** Team, WorkforceRole, and Person
are authored once in git and projected by ArgoCD onto each cluster that has a runtime reader, as a **read-only
mirror** (`selfHeal` + `prune`; the mirror is never hand-edited). **Git stays the single source of truth; a
cluster's copy is a cache.** This generalizes ADR-063's single Team→admission projection to all three records
across all consuming clusters.

**D2 — The hub is both the registry's home and a governed workload cluster.** Because the platform team deploys
governed workloads on the hub, the hub needs the registry for its *own* admission — not only for the
control-plane readers. This collapses the "control-plane cluster vs workload cluster" distinction for
governance: **every cluster runs governed workloads, so every cluster gets the registry.** The hub is simply the
cluster that *also* hosts the control-plane readers (the activation operator, the agents, the portal).

**D3 — Projection is per-consumer, not per-tier.** A record lands on a cluster iff something on that cluster
reads it — there is no blanket "all registries everywhere" rule, just "follow the readers":

| Record | Projected to | Reader(s) |
|--------|--------------|-----------|
| **Team** | every cluster (hub + preprod + prod as it lands) | Kyverno envelope admission (all clusters), the activation operator (notification channel), the triage agent (owner-routing), Backstage |
| **WorkforceRole** | the hub (today) | the activation operator (cap + permission set) |
| **Person** | the hub (today) | the activation operator (eligibility); owner-routing as it grows |

WorkforceRole/Person fan out further only as readers for them appear on other clusters.

**D4 — The CRD schemas are owned centrally, not by a consumer.** The registry *kinds* (Team / WorkforceRole /
Person CRDs) belong in a single **governance-registry chart** installed on every cluster that hosts the registry,
so the schema has one home decoupled from any one reader. Today Team's CRD rides in the *tenant* `environment-api`
chart and the activation operator generates WorkforceRole/Person — both are incidental homes. Consolidating them
is the target; it may be done **incrementally** (the operator may keep hosting WorkforceRole/Person until the
governance chart exists), but the steady state is one schema home.

**D5 — Authorship, the governance/delivery split, and admission are unchanged.** This ADR changes only **where
the records are projected**, not who authors them (platform-authored governance, ADR-063 §2), not the invariant
that nothing a tenant authors widens its own envelope (ADR-062 §4), and not how Kyverno admits. The mirrors stay
read-only; the source stays git.

## Consequences

### Positive

- **Uniform governance everywhere**, including the platform team's own workloads on the hub — no special-cased
  "the control plane is ungoverned" gap.
- The activation operator (and agents) read a **real, live registry** on their own cluster instead of a vendored
  test copy — retiring the operator-hosted WorkforceRole/Person CRDs in favor of the central schema.
- **Adding a cluster is "project the registry there."** When prod comes online, it gets Team (for admission) by
  adding one sync target — no model change.
- One schema home (D4) removes the divergence risk of per-consumer copies.

### Negative / Risks

- **More projections to manage** — up to N clusters × M registries of ArgoCD apps. Mitigated by the per-consumer
  rule (D3): most records land on few clusters; only Team is broad.
- **Ordering** — a registry must reconcile *before* its readers (a Kyverno admission or an operator mint that
  reads it). ADR-063 already handles this for Team via sync-waves; the same applies to the new records.
- **Eventual consistency** — a just-authored record reaches a cluster only after the next ArgoCD sync, so a
  reader can transiently miss it (e.g. a brand-new role). This is the existing Team behavior; ArgoCD `selfHeal`
  converges, and readers fail closed in the meantime (the activation operator already does).

## Alternatives considered

- **Single-cluster registry + cross-cluster reads** (hub operators read Team from preprod over the network):
  rejected — cross-cluster reads at admission/reconcile time are slow, fragile, and couple cluster lifecycles;
  local read-only projection is the platform's established, robust pattern (ADR-048 federation reasoning).
- **Each consumer vendors its own copy of the schema/records:** rejected — guarantees divergence; the activation
  operator's vendored WorkforceRole CRD is precisely the thing this ADR retires.
- **Move Team to the hub only** (off the workload clusters): rejected — Kyverno admission needs Team locally on
  *every* cluster where governed workloads are admitted, which is all of them.

## Related

- [ADR-063](063-team-as-first-class-git-object.md) (Team git-native — this generalizes its projection),
  [ADR-067](067-idp-domain-model.md) (the Team/Product/Service/Environment model; platform-as-a-team),
  [ADR-061](061-tenant-ingress-and-custom-domain-strategy.md) (registries-as-single-source),
  [ADR-048](048-federated-per-cluster-crossplane.md) (per-cluster local reads, not cross-cluster).
- [ADR-088](088-temporary-power-activation.md) (the activation operator — the hub registry consumer driving this),
  [ADR-084](084-platform-identity-directory-and-owner-resolution.md) (owner-routing — Team→Slack on the hub),
  [#887](https://github.com/asanexample/platform/issues/887) (the WorkforceRole catalog).
