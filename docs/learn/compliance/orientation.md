# Learn: Compliance & regulated workloads — orientation

How the platform handles compliance — and an honest account of how much is *built*, how much is *inert*,
and how much is *aspirational*. Short version: **compliance-aware by design, not compliance-certified.**

**Audience:** platform engineers, and anyone asking "could this run a HIPAA or PCI workload?" This module
is a lens over the security modules — [Policy & admission](../policy/orientation.md),
[Supply chain](../supply-chain/orientation.md), [Runtime security](../runtime-security/orientation.md),
[Identity & access](../identity/orientation.md), and [Foundations](../foundations/README.md) (the org SCPs).
It leans on all of them; read at least one first.

## The question

Most platforms treat compliance as a bolt-on: a product you buy, a scanner you run before an audit, a binder
a human assembles. This one bets the other way — that compliance should be a **declared dimension** of every
environment, and that the security controls already built for defense in depth *are* the controls an auditor
cares about.

So: how do you make a platform compliance-aware for regulated workloads (HIPAA, PCI) without bolting on a
compliance product — and how honest can you be about what's actually *enforced* versus merely *designed*?

## The one idea: compliance is a lens and a dial, not a subsystem

Compliance here isn't a subsystem. It's a **lens** over the security modules plus one **dial**. The dial is a
declared **tier** (`standard` / `hipaa` / `pci`) on every environment, constrained by what a team is licensed
for. The controls it modulates already exist — Kyverno admission, signed images, least-privilege IAM,
encryption, network default-deny, the org SCPs.

But the dial is turned to `standard` everywhere. No regulated tenant exists, the regulated settings don't
render on the running clusters, and the machinery that turns "a control exists" into "here is continuous
*proof* it's enforced" is only partly built — violation signals stream to Grafana, but the framework-mapped
catalog and evidence store don't exist yet.

Three things follow, told honestly:

1. **The dial is real and wired** — `tier` is a first-class field, envelope-constrained and admission-enforced.
2. **The controls are real and live** — but they run *uniformly* at `standard`; the dial modulates almost
   nothing today.
3. **The assurance layer is only partly built** — Kyverno violations already stream to Grafana as evidence,
   but the framework-mapped audit trail isn't printed yet.

The picture to hold: a building rated for a hazard class it has never had to withstand. The blueprints
specify seismic reinforcement for a high-hazard zone — that's the tier model, designed into every floor plan.
Where it breaks: the reinforcing steel isn't installed in the two buildings that are actually *occupied*,
because both sit in the standard zone. The rating is honest about intent; it is not a certificate of installed
protection.

## Stop 1 — the dial: `tier` as a declared, constrained dimension (built)

Compliance starts in the data model. Every environment's `XEnvironment` claim carries a **`spec.tier`** — a
hardening profile that bundles an isolation floor, an encryption floor, a network default, and a retention
floor under one label. There are three: `standard` (SOC 2 baseline), `hipaa`, and `pci`, each with a
prescriptive control table. The tier sets a
floor: effective isolation is `max(tier-floor, what-you-asked-for)`.

You can't just claim a regulated tier. A team may only request tiers inside its
**`Team.spec.envelope.allowedTiers`**, and that's enforced at admission by the Kyverno
`restrict-environment-envelope` policy (rule `tier-within-envelope`), which reads the team's envelope and
denies a `spec.tier` the team isn't licensed for. The same policy enforces the sibling axes the same way —
`stage-within-envelope` and residency (`allowedLocations`) — so which tiers, stages, and regions a team can
even ask for is one governed envelope. It's Enforce on preprod today (Audit/off on the hub). This part works:
the dial exists, and you can't turn it past your license.

One honest wrinkle. The tier enum has drifted across three sources — the XRD lists four values
(`standard`/`elevated`/`pci`/`hipaa`), while the policy module lists three (no `elevated`).
`elevated` is an accepted claim value that maps to no differentiated behavior — a small data-model
inconsistency, exactly the kind a compliance audit would flag. There's also a stray invalid
`compliance_tier = "high"` in the *undeployed* prod config, harmless only because prod isn't real yet.

## Stop 2 — the controls: compliance rides on the security modules (built, but uniform)

Here's the honest strength. The platform never built a separate compliance engine — its existing security
controls *are* the compliance controls. An auditor's checklist maps almost one-to-one onto modules that
already exist for defense in depth:

| Auditor asks about… | …and the platform already has |
| --- | --- |
| preventive config controls | **Kyverno** admission (Enforce) — [Policy](../policy/orientation.md) |
| software integrity / provenance | **cosign + SLSA L3** — [Supply chain](../supply-chain/orientation.md) |
| least privilege / authorization | **Pod Identity + deny-set IAM** — [Identity](../identity/orientation.md) |
| encryption in transit | **WireGuard + SPIRE mTLS** — [Runtime security](../runtime-security/orientation.md) |
| network segmentation | **NetworkPolicy default-deny** + namespace isolation |
| preventive guardrails at the account | the **org SCPs** (encryption-at-rest, region residency, IMDSv2, …) |
| audit trail | **CloudTrail** (deployed on both clusters) |
| runtime detection | **Falco** (deployed on both clusters) |

So `tier` and `residency` are the dial; these subsystems are the controls it modulates. But today the dial
modulates almost nothing. The only place `tier` changes admission behavior is two Kyverno policies
(`require-pod-security-restricted` + `require-ro-rootfs`, which add Restricted-PSS and a read-only root
filesystem on regulated tiers). And they're gated per cluster, not per namespace — so a regulated tier means
a whole dedicated cluster. Both live clusters are `standard`, so those two policies don't
render at all — they exist in code and unit tests only. Everything else — image scoping, RBAC hardening,
probes, cosign verification, the SCPs, CloudTrail, Falco — is tier-independent, and every environment gets it,
`standard` included. The controls are strong and live; they just run uniformly, and the regulated dial-setting
has never been turned.

No regulated tenant exists. Every environment in git is `tier: standard`; every team's `allowedTiers` is
`["standard"]`. No team is even licensed for a regulated tier. The regulated path has never been walked.

## Stop 3 — the gap: assurance & evidence (partly built, mostly designed)

Strong controls aren't the same as proof the controls are enforced. That bridge — from "a control exists" to
"here is continuous, tenant-attributable evidence it's enforced" — is only partly built. Of its three pieces:

- a **control catalog as code** mapped to framework IDs — unbuilt.
- **continuous scanning** that aggregates the signals that already exist (Kyverno PolicyReports, attestations,
  AWS Config) into a live control-status view — the Kyverno-PolicyReport→Grafana slice of this is already live
  (the `observability-policy-reporter`, on both clusters, alerting on policy violations as compliance
  evidence); the framework mapping, multi-source aggregation, and Backstage view are not.
- **evidence collection** into retention-locked storage — unbuilt.

The other down-payment, alongside that live PolicyReport observability, is a thorough hand-maintained document
— `docs/compliance/scp-control-mapping.md` — mapping the org SCPs to SOC 2 / HIPAA / PCI / ISO 27001 /
NIST 800-53 / CIS control IDs, with copy-paste auditor queries. Useful, but exactly the manual archaeology
the assurance layer exists to replace — nothing generates or continuously verifies it.

Think of it as a security system whose audit-trail printer is only half-installed. The sensors — Kyverno,
CloudTrail, the SCPs, Falco — are all wired and firing, and Kyverno's violations *are* streamed to Grafana as
compliance evidence. But the framework-mapped report — "here's continuous proof control X satisfies PCI
requirement Y for tenant Z" — still isn't printed; that evidence is a person running SQL from a Markdown file.

## The honest status — the whole module in one ledger

- **Built + live:** `tier` as a first-class data-model dimension (plus a `ComplianceTier` tag on resources);
  the envelope validation (`allowedTiers`/`allowedStages`/residency/quota — Enforce on preprod); and all the
  underlying security controls compliance rides on (Kyverno, supply chain, Pod Identity, WireGuard, SCPs,
  CloudTrail, Falco).
- **Built but inert:** the regulated-tier hardening (Restricted-PSS + RO-rootfs) — real in code, but it
  doesn't render on either cluster (both `standard`), and there's no per-namespace tier differentiation. No
  regulated tenant or team exercises it.
- **Partly built:** continuous scanning has a live first slice — the Kyverno-PolicyReport→Grafana
  `observability-policy-reporter` (both clusters, alerting on violations as compliance evidence).
- **Designed / aspirational:** the framework control-catalog-as-code, multi-source aggregation plus the
  Backstage control-status view, and retention-locked evidence collection; K8s API-server audit-log shipping.

Said plainly: the platform is architected so that going regulated is a dial-turn, not a rebuild — but the dial
is at `standard` everywhere, the regulated settings are unproven in production, and the certify-and-prove
machinery is mostly a strategy, one live slice (PolicyReport→Grafana) aside, not yet a system. That honesty
*is* the teaching.

## Go deeper

The lookup: the [Reference](reference.md). This module rides on:
[Policy & admission](../policy/orientation.md) · [Supply chain](../supply-chain/orientation.md) ·
[Runtime security](../runtime-security/orientation.md) · [Identity & access](../identity/orientation.md) ·
[Foundations](../foundations/README.md). The
static control map: `docs/compliance/scp-control-mapping.md`.
