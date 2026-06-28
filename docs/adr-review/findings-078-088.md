# ADR Accuracy Review — ADRs 078–088 + Index

Checkout: `/Users/josh/centric/platform-adr-review` (worktree at origin/main).

---

## ADR-078: Cluster Elasticity — Karpenter + Workload Autoscaling
- **Status quoted:** `Accepted — Phase 1 (Karpenter) implemented + live on both clusters, 2026-06-23 (#643). Phase 2 (HPA/KEDA on the paved road) outstanding.`
- **Findings:**
  - [SEVERITY: low] Status/phasing/as-built accurate. `karpenter` module + live units on **both** clusters; `min_instance_memory_mib = 6144` both; system group `t4g.large → t4g.xlarge`; `cloudwatch_enabled`/Pod-Identity present. — **Evidence:** `infra/live/aws/{platform,preprod}/us-east-1/platform/karpenter/terragrunt.hcl`; `node-groups/terragrunt.hcl:48,64`. — **Proposed fix:** none.
  - [SEVERITY: low] The SCP-exemption note (line 134-135) says controller role pattern **`*-karpenter-*`**, but live org config deliberately moved **off** the leading-wildcard form to per-cluster–scoped patterns (documented security fix). — **Evidence:** `infra/live/aws/mgmt/global/organizations/terragrunt.hcl:26-31` vs ADR line 135. — **Proposed fix:** update to the scoped `platform-use1-eks-karpenter-*` / `preprod-use1-eks-karpenter-*` pattern.
- **Decision concerns:** none.

## ADR-079: Cloud-Resource Monitoring Scope — Query-Time-First in Grafana
- **Status quoted:** `Accepted — P5a (Grafana CloudWatch metrics + Logs datasource) and P5b (YACE → Mimir) built + live on the platform hub; … (2026-06-24)`
- **Findings:**
  - [SEVERITY: low] Verified: `cloudwatch_enabled` provisioned; YACE curated set exactly `AWS/NetworkELB`/`AWS/NATGateway`/`AWS/TransitGateway` matching D2. — **Evidence:** `infra/modules/observability/main.tf:6,319`; `observability-cloudwatch-exporter/main.tf:20-48`. — **Proposed fix:** none.
- **Decision concerns:** none.

## ADR-080: The Triage Copilot — Propose-Only On-Call Incident Triage
- **Status quoted:** `Accepted (2026-06-24) — agent built + live`
- **Findings:**
  - [SEVERITY: medium] Internal-consistency staleness: D6 still asserts "the agent build is de-risked to proceed; **the ADR stays Proposed until that build is actually pulled**" (line 233), contradicting the header (`Accepted … built + live`) and the as-built section. — **Evidence:** line 233 vs lines 3, 425-451. — **Proposed fix:** edit D6's closing sentence to past tense.
  - [SEVERITY: low] Model-tier claims (D8: Sonnet 4.6 / Haiku 4.5 / Opus 4.8) + inference-profile id `us.anthropic.claude-sonnet-4-6` live in the external `asanexample/platform-triage-copilot` repo. — **NEEDS LIVE/OWNER VERIFICATION**.
- **Decision concerns:** Long, thorough, coherent; only the lingering "stays Proposed" line creates a contradiction.

## ADR-081: Platform-Team Products on the One Delivery Road
- **Status quoted:** `Proposed (2026-06-24) · Runtime-placement decision (D2/D3) superseded for platform agents by ADR-082 (2026-06-25)`
- **Findings:**
  - [SEVERITY: low] Status + amendment internally consistent and match README + ADR-082's reciprocal language. — **Evidence:** README:130; ADR-082:46-49. — **Proposed fix:** none.
- **Decision concerns:** none.

## ADR-082: The `XAgent` Platform-Agent Runtime
- **Status quoted:** `Accepted (2026-06-25) — built + live (2026-06-26)`
- **Findings:**
  - [SEVERITY: low] Strongly grounded — every named artifact exists: `gitops/agents/triage-copilot.yaml`, `crossplane/charts/agent-api/` (XRD, composition, trust cluster roles), `agent-policies` chart with `restrict-agent-envelope`, `.github/scripts/gitops-gate/validate-agents.sh`, `argocd-apps/agents.tf`. Spec fields match D1. — **Evidence:** commands. — **Proposed fix:** none.
- **Decision concerns:** none — exemplary as-built fidelity.

## ADR-083: Provider Version-Constraint Standardization
- **Status quoted:** `Accepted` (Date: 2026-06-26)
- **Findings:**
  - [SEVERITY: medium] The universal present-tense claim is contradicted by the repo. ADR says "**All ~58 shared modules now state a consistent, honest provider contract**," but three modules predating the ADR still float kubernetes with unbounded `>=`: `cluster-rbac` (`>= 2.10.0`), `observability-k6` (`>= 2.35.0`), `argocd-clusters` (`>= 2.35.0`); one helm `>= 3.0` outlier too. (A fourth, `oauth2-proxy` `>= 2.0`, postdates the ADR — drift-since, not a miss.) — **Evidence:** `grep -rh -A1 hashicorp/kubernetes infra/modules --include=versions.tf` → 1×`>=2.0`, 1×`>=2.10.0`, 2×`>=2.35.0`, 22×`~>3.0`. — **Proposed fix:** either bound those modules to `~> 3.0` or soften the ADR's "All … now" to "all but a handful of stragglers (tracked)."
  - [SEVERITY: low] The "Out of scope" wrinkle (root.hcl `aws = "6.47.0"` exact) has since been resolved — `infra/root.hcl:31` documents the pin was removed. — **Proposed fix:** optional "(resolved since)" note.
- **Decision concerns:** Sound decision; only the completeness claim over-reaches.

## ADR-084: Platform Identity Directory and Owner Resolution
- **Status quoted:** `Proposed` (Date: 2026-06-26)
- **Findings:**
  - [SEVERITY: medium] Status stale/under-stated. The amendment says Phase 0 was implemented (#834), the `platform` Team ownership block is live, and **Phase 2 foundation shipped** (`infra/modules/pagerduty` + live unit, commit `6c7e4e68` "ADR-084 Phase 2 foundation"). Bare "Proposed" understates reality. — **Evidence:** `gitops/teams/platform.yaml`; `infra/modules/pagerduty/`; git log #932. — **Proposed fix:** "Proposed — Phase 0 built + live; Phase 2 (PagerDuty) foundation landed (#932); Phases 1/3 outstanding."
- **Decision concerns:** Design coherent; phasing/status label lags the code.

## ADR-085: Workload Availability — Graceful Draining & Disruption-Tolerance Defaults
- **Status quoted:** `Proposed` (Date: 2026-06-26)
- **Findings:**
  - [SEVERITY: high] Status is **wrong** — built and live on **both** clusters and the replica-floor rule is now in **Enforce**, yet the header says "Proposed." Machinery exists (`mutate-pod-defaults.yaml` `preStop.sleep` + `terminationGracePeriodSeconds: 30`, `mutate-topology-spread.yaml`, `require-replica-floor.yaml`); both live units set `replica_floor_failure_action = "Enforce"`; commit `a58ff22d` "flip replica-floor to Enforce (#934)." A "Proposed" status on a policy that now **rejects** prod deploys is operationally misleading. — **Evidence:** `infra/live/aws/{platform,preprod}/us-east-1/platform/policy/terragrunt.hcl`; policy chart templates; git log #934. — **Proposed fix:** "Accepted — built + live both clusters 2026-06-26; replica-floor flipped to Enforce 2026-06-27 (#934)."
  - [SEVERITY: medium] **File defect:** the markdown ends with stray tool-call XML — `</content>` (line 191) and `</invoke>` (line 193) — leaked into the committed ADR. — **Evidence:** `tail -5 … | cat -A`. — **Proposed fix:** delete the trailer (lines 191-193).
- **Decision concerns:** Decision content strong; the status label + trailing artifact are the problems.

## ADR-086: Autonomous Agent Access — Graduated Autonomy under Machine-Enforced Guardrails
- **Status quoted:** `Proposed (draft / sketch — 2026-06-27)`
- **Findings:**
  - [SEVERITY: low] Status honest (explicitly draft/sketch). Cross-ref `../architecture/identity-and-access-strategy.md` §3.4 resolves. — **Proposed fix:** none.
  - [SEVERITY: low] **Cosmetic defect:** trailing "🤖 Generated with [Claude Code]" footer (line 157) that doesn't belong in an ADR (also leaked into 068/069/070). — **Evidence:** `grep -l "Generated with \[Claude Code\]" docs/adrs/*.md`. — **Proposed fix:** remove the footer.
- **Decision concerns:** none.

## ADR-087: Keycloak Admin-Plane Hardening — master-realm passkey + sealed break-glass
- **Status quoted:** `Proposed (2026-06-27)`
- **Findings:**
  - [SEVERITY: medium] Status stale: hardening is **built and bound live** on platform. The live unit sets `manage_master_admin = true` **and** `enforce_master_browser_mfa = true`; commit `2cbd618a` "bind the master-realm passkey flow (apply-2, #899)" completes the two-apply rollout. (Internal mismatch: the live-unit comment says "bind deferred to enrollment" while enforce is true — owner should confirm the master `admin` passkey was enrolled before the bind.) — **Evidence:** `infra/live/aws/platform/us-east-1/platform/keycloak-config/terragrunt.hcl:222-226`. — **Proposed fix:** "Accepted — built + bound live on platform 2026-06-27 (#899/#935)."
  - [SEVERITY: low] Keycloak `26.6.3` (Consequences line 29) matches module default `infra/modules/keycloak/variables.tf:72`. — **Proposed fix:** none.
- **Decision concerns:** none — only the status lags the same-day implementation.

## ADR-088: Temporary-Power Activation — just-in-time elevation & emergency revocation
- **Status quoted:** `Proposed (design — 2026-06-27)`
- **Findings:**
  - [SEVERITY: low] Status honest (design-only / demonstration-scale; P3 of epic #884). Cross-refs to `identity-and-access-strategy.md` resolve. — **Proposed fix:** none.
- **Decision concerns:** none.

## Index (README.md)
- **Findings:**
  - [SEVERITY: high] Row for ADR-085 reads `Proposed` (README:108) — stale; it is built + live both clusters with replica-floor enforced. — **Proposed fix:** change to `Accepted`.
  - [SEVERITY: high] (from ADR-056 reviewer) Row for ADR-056 reads `Proposed` (README:107) — stale; the ADR is `Accepted` and repo-corroborated. — **Proposed fix:** change to `Accepted`.
  - [SEVERITY: medium] Rows for ADR-084 (README:98) and ADR-087 (README:110) read `Proposed` but both shipped material. — **Proposed fix:** annotate the phase/built state (ADR-078 style).
  - [SEVERITY: medium] **Miscategorization.** ADR-085/086/087/088 are all filed under "Supply Chain & Delivery" (README:108-111), but 086 (autonomous agent access) belongs with the agentic ADRs, and 087/088 (Keycloak hardening / temporary-power) belong under "Workload & Human Identity." — **Proposed fix:** move 086 → Agentic, 087/088 → Workload & Human Identity, consider 085 next to 078.
  - [SEVERITY: low] All 11 in-scope ADRs (078-088) present, no dupes/gaps; theme-grouped numbering is the index convention, not an error.
  - [SEVERITY: low] Title-truncation nit: README:129 short-titles ADR-080. Cosmetic.
- **Decision concerns:** none.

---

## Cross-cutting note

Two themes. (1) **Status lag on just-shipped ADRs:** 085 (high), 084 + 087 (medium), and 080's internal "stays Proposed" line — several decisions written the same day they shipped kept a "Proposed" header while the code (and CLAUDE.md) treat them as live/enforced. The index inherits the same lag (085 + 056 rows especially). 085 is the priority because its policies now reject admission. (2) **Leaked authoring artifacts:** stray `</content>`/`</invoke>` tool-call XML at the tail of ADR-085 (and 056), and a "Generated with Claude Code" footer in ADR-086 (and 068/069/070) — a recurring drafting-harness contamination that should be grep-swept across `docs/adrs/`.
