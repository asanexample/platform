# Learn: Compliance & regulated workloads — reference

Look-up, not a lesson. Build the model in the [orientation](orientation.md) first. Verified against code +
ADRs. No account IDs or emails appear here. This is a short module (no deep dives) — compliance is a *lens*
over the security modules, not a subsystem.

## The model

**Compliance-aware by design, not certified.** Two moving parts: a **lens** (the platform's existing security
controls *are* the compliance controls — compliance *maps* them, it doesn't rebuild) and a **dial** (a
declared `tier` per environment, envelope-constrained). Honest one-liner: *going regulated is a dial-turn, not
a rebuild — but the dial is at `standard` everywhere, the regulated settings are unproven in production, and
the certify-and-prove machinery is *mostly* designed (one live slice — PolicyReport→Grafana — aside).*

## Tier model — [ADR-013](../../adrs/013-compliance-tier-model.md) (Accepted; built as a data-model dimension)

- **`spec.tier`** on the `XEnvironment` claim = a **hardening profile** bundling an isolation floor +
  encryption floor + network default + retention floor under one label. A *floor*: effective isolation =
  `max(tier-floor, spec.isolation.compute)`. Default `standard`. A `ComplianceTier` tag propagates to
  resources via `_base.hcl`.
- **Tiers (ADR-013 + policy module):** `standard` (SOC 2 baseline), `hipaa`, `pci` — each with a prescriptive
  control table (compute/network isolation, encryption at rest + host, netpol default, WAF/IDS, log retention).
- **Enum drift (flag it):** the XRD (`xenvironment-xrd.yaml` ~L68-71) lists **four** —
  `["standard","elevated","pci","hipaa"]` — adding `elevated`, which appears nowhere in ADR-013 or the policy
  module and **maps to no differentiated behavior**. Also a stray invalid `compliance_tier = "high"` in the
  *undeployed* `prod/…/workload.hcl` (harmless only because prod isn't real). Two data-model inconsistencies
  an audit would flag.

## Envelope validation — the constraint (Enforce on preprod)

A team can only request tiers/stages/regions it's licensed for. The Kyverno **`restrict-environment-envelope`**
ClusterPolicy (`infra/modules/crossplane/charts/environment-policies/templates/environment-envelope.yaml`)
reads the projected `Team` CR and denies out-of-envelope claims across four axes:

- **`tier-within-envelope`** — `spec.tier ∈ Team.spec.envelope.allowedTiers`.
- **`stage-within-envelope`** — `spec.stage ∈ allowedStages`.
- **`residency-within-envelope`** — `spec.residency.allowedLocations ⊆ allowedLocations` (residency wired
  identically to tier).
- quota ≤ `quotaCap`; `policystatements-no-escalation` (deny-set IAM).

**Live:** `enableEnvironmentEnvelope = true`, `envelopeFailureAction = "Enforce"` on **preprod**; module
default is `false`/`Audit` (the hub isn't enforcing it yet).

## What the tier actually toggles today (built but INERT)

- **The only tier-conditional behavior** is in `pod-hardening.yaml` (~L78): `{{- if ne .Values.complianceTier
  "standard" }}` gates two policies — **`require-pod-security-restricted`** (full Restricted PSS) +
  **`require-ro-rootfs`** (`readOnlyRootFilesystem: true`).
- **It's a per-CLUSTER Helm-render gate, not per-namespace.** `complianceTier` is one module input from
  `workload.hcl` per cluster; the policies key on the environment-namespace selector (the
  `platform.refplat.org/team` label), not a per-namespace tier label. So a regulated **cluster** hardens *all*
  its env workloads — matching ADR-013's whole-dedicated-cluster-as-regulated model.
- **Both live clusters are `standard`** → `ne "standard"` is false → **these two policies don't render at
  all.** They exist in code + unit tests only — not merely unexercised, *absent* from the running policy set.
- **Everything else is tier-independent** — image-registry scoping, `rbac-hardening` (`restrict-binding-
  clusteradmin`, `restrict-wildcard-rbac`), probes, requests/limits, automount-off, no-LoadBalancer,
  no-`:latest`, cosign verify — every environment gets it, `standard` included. The regulated tiers only *add*
  the two policies on top.
- **No regulated tenant.** Every `gitops/environments/**` claim is `tier: standard`; every team's
  `allowedTiers` is `["standard"]`. No team is even *licensed* for a regulated tier.

## Compliance rides on the security modules (the controls are real + live)

The existing defense-in-depth controls *are* the compliance controls (ADR-055's thesis: map, don't build):

| Control | Where | Compliance role |
| --- | --- | --- |
| Kyverno admission (Enforce) | [Policy](../policy/orientation.md), ADR-014 | preventive config controls |
| cosign + SLSA L3 | [Supply chain](../supply-chain/orientation.md), ADR-042 | software integrity / provenance |
| Pod Identity + deny-set IAM | [Identity](../identity/orientation.md), ADR-041/047 | least privilege / authorization |
| WireGuard + SPIRE mTLS | [Runtime security](../runtime-security/orientation.md), ADR-057 | encryption in transit |
| NetworkPolicy default-deny | per-environment | network segmentation |
| 8 org SCPs | `organizations` module | account-level preventive guardrails |
| CloudTrail (deployed both clusters) | `aws/cloudtrail`, ADR-037 | audit trail |
| Falco (deployed both clusters) | [Runtime security](../runtime-security/orientation.md), ADR-045 | runtime detection |

`tier`/`residency` are the *dial*; these are the *controls* it's meant to modulate — but today it modulates
only the two (unrendered) PSS policies, and everything runs uniformly at `standard`.

## Assurance & evidence — [ADR-055](../../adrs/055-compliance-assurance-and-continuous-control-evidence.md) (Proposed; partly built)

- **The gap:** strong *controls*, no *assurance* — no bridge from "a control exists" to "continuous,
  tenant-attributable proof it's enforced."
- **The three proposed pieces:** (1) a **control catalog as code** mapped to SOC 2 / PCI / HIPAA IDs; (2)
  **continuous scanning** aggregating signals that already exist (Kyverno **PolicyReports**, attestations, AWS
  Config/Security Hub) into a live control-status view (Grafana + Backstage); (3) **evidence collection** into
  retention-locked (S3 Object Lock) storage, per-tenant-attributable.
- **Built (a real first slice):** the **`observability-policy-reporter`** module (P12, #93) is deployed on
  *both* clusters — it turns Kyverno **PolicyReport**/ClusterPolicyReport CRs into Prometheus metrics + Grafana
  dashboards, with live alerts (`PolicyReportNewViolation`, …) whose own comment calls policy fail/error
  results *compliance evidence worth paging on*. So piece (2)'s **Kyverno→Grafana half is live.** Plus the
  hand-maintained static `docs/compliance/scp-control-mapping.md` (8 SCPs → SOC 2 / HIPAA / PCI / ISO 27001 /
  NIST 800-53 / CIS, with copy-paste auditor queries).
- **Still unbuilt:** the framework **control catalog as code** (1); the **multi-source** aggregation + the
  **Backstage** control-status view (rest of 2); **retention-locked evidence collection** (3).
- **Also not built:** K8s API-server audit-log shipping + its roll-up into evidence (distinct from the deployed
  CloudTrail).

## Status ledger

- **Live:** `tier` data-model dimension + `ComplianceTier` tag; envelope validation (tiers/stages/residency/
  quota — Enforce preprod); the underlying security controls (Kyverno, supply chain, Pod Identity, WireGuard,
  SCPs, CloudTrail, Falco).
- **Built but inert:** regulated-tier hardening (Restricted-PSS + RO-rootfs) — doesn't render on either
  `standard` cluster; no per-namespace differentiation; no regulated tenant/team.
- **Partly built:** ADR-055's continuous scanning has a live slice — the Kyverno-PolicyReport→Grafana
  `observability-policy-reporter` (both clusters).
- **Designed / aspirational:** ADR-055's framework control-catalog, multi-source aggregation + Backstage view,
  evidence collection; K8s API-audit shipping.

## Gotchas

- **"Which tier are we?"** Both live clusters are `standard` — the regulated policies aren't running.
- **Tier enum drift** — XRD has `elevated` (maps to nothing); ADR-013/module don't. Prod has an invalid
  `"high"` (harmless — prod undeployed).
- **Regulated = a whole cluster**, not a namespace toggle (per-cluster `complianceTier` render gate).
- **"Show me the evidence"** — Kyverno violations are live in Grafana (`observability-policy-reporter`), but
  the *framework-mapped* control catalog + retention-locked evidence store aren't built; the SCP→framework
  mapping is a hand-maintained doc.
- **CloudTrail is deployed** (the "audit-logging off" lore is stale) — what's missing is *K8s API-server*
  audit + evidence aggregation.

## Go deeper

Rides on: [Policy](../policy/orientation.md) · [Supply chain](../supply-chain/orientation.md) ·
[Runtime security](../runtime-security/orientation.md) · [Identity](../identity/orientation.md) ·
[Foundations](../foundations/README.md). ADRs:
[013](../../adrs/013-compliance-tier-model.md) (tier model, Accepted) ·
[055](../../adrs/055-compliance-assurance-and-continuous-control-evidence.md) (assurance, Proposed).
The static control map: `docs/compliance/scp-control-mapping.md`. External:
[HIPAA Security Rule](https://en.wikipedia.org/wiki/Health_Insurance_Portability_and_Accountability_Act) ·
[PCI DSS](https://www.pcisecuritystandards.org/) ·
[Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/).
