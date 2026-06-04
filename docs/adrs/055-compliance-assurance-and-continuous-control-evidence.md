# ADR-055: Compliance Assurance & Continuous Control Evidence

**Date:** 2026-06-04

**Status:** Proposed — **strategy/direction.** Turns the platform's existing technical controls into
*audit-ready, continuously-verified assurance*. Builds on the compliance-tier model
([ADR-013](013-compliance-tier-model.md)/[ADR-049](049-tenant-model-team-tenant-zone.md)),
[ADR-014](014-kyverno-as-policy-engine.md) (admission), [ADR-037](037-cloudtrail-audit-logging.md) (audit log),
the supply chain ([ADR-042](042-isolated-build-provenance-slsa-l3.md)), [ADR-045](045-falco-runtime-threat-detection.md)
(runtime), and the partial start in [`docs/compliance/scp-control-mapping.md`](../compliance/scp-control-mapping.md).

## Context

The platform has **strong technical controls** — Kyverno admission, cosign/SLSA supply chain, CloudTrail,
Falco, SCPs, NetworkPolicies, Pod Identity, the compliance tiers. What it lacks is **assurance**: the bridge
from "a control exists" to "here is continuous proof it is enforced for tenant Y." Specifically missing:

- **No control → framework mapping.** Controls aren't mapped to SOC2 / PCI-DSS / HIPAA control IDs, so an audit
  is a manual archaeology exercise. Only SCPs have a partial mapping today.
- **No continuous verification.** Kyverno emits PolicyReports and CloudTrail logs events, but nothing
  aggregates them into a live "are the controls actually holding?" signal.
- **No evidence collection.** Audit evidence (policy reports, attestations, access reviews) isn't gathered into
  durable, attributable, retention-locked storage.

An auditor's question — "prove control X is continuously enforced for this regulated tenant" — currently has no
systematic answer. This blocks regulated prod and customer compliance contracts.

## Decision

1. **A control catalog as code, mapped to frameworks.** One catalog where each control = `{id, description,
   implementing mechanism, applicable tiers}` mapped to SOC2/PCI/HIPAA control IDs. Extends
   `scp-control-mapping.md` to *all* enforcement points (Kyverno policies, SCPs, supply-chain gates, RBAC,
   network policy). The catalog lives **with the mechanisms** so control and implementation can't silently
   drift.
2. **Continuous compliance scanning.** Aggregate the signals that already exist — Kyverno **PolicyReports**,
   supply-chain **attestations**, and cloud posture (**AWS Config / Security Hub**, or an OSS equivalent) — into
   a live control-status signal, surfaced in the observability stack and Backstage. Audit-mode policies are
   *findings*; enforce-mode are *gates*.
3. **Evidence collection + retention.** Control evidence is collected to durable, **retention-locked** storage
   (shares the S3 Object Lock / retention story with [ADR-054](054-platform-resilience-and-business-continuity.md);
   complements CloudTrail, ADR-037). Evidence is **per-tenant-attributable** via the tenant model's Team/Zone
   labels.
4. **Assurance is reported per tier / regime.** The compliance tier (ADR-049) selects the applicable control
   set; the catalog + scanner report posture per tier and per regulatory regime.

## Alternatives considered

- **A commercial GRC platform (Vanta/Drata) as the foundation.** Good for audit logistics, but the control
  *evidence* must originate from the platform regardless — a GRC tool consumes evidence, it doesn't enforce.
  Rejected as the foundation; may sit *on top* for audit workflow.
- **Point-in-time audits only.** Doesn't scale and isn't continuous; a control can regress between audits.
  Rejected.
- **Trust the controls without evidence.** "Enforced" ≠ "provable." Rejected — the gap this ADR exists to
  close.

## Consequences

- Converts an already-strong control surface into **audit-ready posture**; unblocks regulated prod + customer
  compliance contracts.
- The control catalog must be **maintained alongside the policies** — co-location is the mitigation, but it's
  ongoing discipline.
- Backstage and the observability stack gain a **compliance view** (per-tenant control status).
- Reuses retention-locked storage and audit logging already decided elsewhere — incremental, not greenfield.
- **Open:** the cloud-posture scanner choice (AWS Config vs OSS), and the exact GRC-tool boundary.
