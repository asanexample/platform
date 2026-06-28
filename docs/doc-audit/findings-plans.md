# Documentation Audit — docs/plans/ + archive/compliance/examples

Checkout: `/Users/josh/centric/platform/.claude/worktrees/doc-audit` @ origin/main. Clusters parked; verification against repo only.

## docs/plans/056-progressive-delivery.md

- [SEVERITY: low] Honestly framed and accurate. Status block (2026-06-27) correctly marks Phases 0–2 DONE, Phase 3 W11 done / W10 deferred. `infra/modules/argo-rollouts` exists with live units on both clusters + `rollouts-sso`; scaffolder skeleton emits `kind: Rollout`. (Note: user MEMORY saying ADR-056 "NOT built" is the stale artifact, not this plan.) — **Recommended fix:** none; model for how a point-in-time plan should carry a dated status.

## docs/plans/080-triage-copilot-eval-spike.md

- [SEVERITY: low] Honestly framed — opens "Proposed" but closes with a dated "Results — GO ✅ (executed 2026-06-24/25)" section that self-corrects the stale "logs/traces spokes unbuilt" line. — **Recommended fix:** optionally move to `docs/archive/` since the spike is closed.

## docs/plans/085-workload-availability-defaults.md

- [SEVERITY: medium] **Completed work written entirely in future tense with no status header.** The whole plan (W0–W6, "flip W3 to Enforce") reads as pending, but ADR-085 is merged + applied live on both clusters and the replica floor is now **Enforce**. — **Evidence:** both live policy units set `replica_floor_failure_action = "Enforce"`; module default still `Audit` (`policy/variables.tf:188`). — **Recommended fix:** add a dated "Status: DONE / applied live (#934)" header like 056 has; move to `docs/archive/`.
- [SEVERITY: low] Otherwise technically accurate to the as-built (mutate preStop/terminationGracePeriod, generate-pdb, validate replica-floor, Karpenter terminationGracePeriod).

## docs/plans/102-observability-stack.md

- [SEVERITY: medium] **Stale `teams.hcl` / tenant-model framing throughout.** The "Tenancy spine" (line 33), "Module/unit pattern" ("Per-team data as maps at the unit from `teams.hcl`", line 168), and P13/P14 (343, 347, 476-480) all key tenancy off `teams.hcl`, retired (ADR-061/063/067). — **Evidence:** `find . -name teams.hcl` → nothing. — **Recommended fix:** update to derive from the `Team` CR / Product registry, or add a status note.
- [SEVERITY: medium] **Wrong namespace label.** Tenancy spine says tenant is stamped "from the namespace label `platform.refplat.org/tenant`" (line 34); also security model §1c. Live label is `platform.refplat.org/team`. — **Evidence:** `grep platform.refplat.org/(team|tenant)` → 10× `/team`, 0× `/tenant`. — **Recommended fix:** s/`/tenant`/`/team`/.
- [SEVERITY: low] P10 body (321-328) still calls logs/traces spokes "follow-ons," but they are built — `preprod/.../observability-{logs,traces}-spoke/` exist. — **Recommended fix:** update P10 paragraph.
- [SEVERITY: low] P11 "remaining" framing is honest: OpenCost live; CUR→Athena half genuinely not built.

## docs/plans/131-slsa-build-l3.md

- [SEVERITY: medium] **"P4 remaining" is stale — P4 (platform cluster) is effectively done.** Status (1-7) says "P4 … is the remaining step," but the platform policy unit now enforces provenance attestation. — **Evidence:** `platform/.../policy/terragrunt.hcl:119` `attest_failure_action = "Enforce"` (and `verify_failure_action = "Enforce"`). — **Recommended fix:** mark P4 done; move to `docs/archive/`.
- [SEVERITY: medium] **Describes the superseded per-team (v2) model** (`verify-attestations-team-<team>`, `app-<team>`, per-team attestor identity); live policy is product-scoped (`verify-attestations-product.yaml`; `verify_subjects_product` from `gitops/products`). — **Recommended fix:** note product-keyed (v3) or archive as historical.

## docs/plans/adr-071-digest-promotion-implementation.md

- [SEVERITY: medium] **No status block; reads as pending, but the `Release` control-plane digest-promotion is implemented and live.** PR1–PR7 ("Flip ADR-071 → Accepted") are future-tense. — **Evidence:** `docs/examples/compliant-deployment.yaml:38-39` documents the live behavior; `gitops/releases/**`. — **Recommended fix:** add a dated DONE status (or per-PR ✅) and archive; confirm ADR-071 Accepted.
- [SEVERITY: low] Uses v2-era `app-<team>` / `Pod-<team>-<name>-<env>` (pre-v3) — internally consistent but off the current `<team>-<product>-<stage>` model.

## docs/plans/cost-optimized-dev-rebuild.md

- [SEVERITY: medium] **"Status: proposed (not yet implemented)" but its core levers are shipped.** `platctl down/up` (Part C) exists and is a house skill (`cluster-parking`); Karpenter (deferred "NOT now" here) is live Phase 1 (ADR-078). — **Recommended fix:** update status (down/up shipped, Karpenter Phase-1 live) or archive; flip the "Karpenter — NOT now" framing.
- [SEVERITY: low] `golang:1.24-alpine` snippets lag the repo's Go 1.26 baseline — illustrative app-repo snippets, low.

## docs/plans/slsa-l3-provenance-cutover-HANDOFF.md

- [SEVERITY: medium] **The doc's own deletion condition is met — delete/archive.** Header: "✅ COMPLETE … the only remaining step is P4 … can be deleted once P4 lands." P4 has landed (platform `attest_failure_action = "Enforce"`). — **Recommended fix:** delete or move to `docs/archive/`.
- [SEVERITY: low] Live "NEXT STEPS" working notes are inherently stale.

## docs/plans/tenant-api-v2-and-identity-delivery.md

- [SEVERITY: medium] **Superseded plan, not marked.** This is the v2 (`XTenant`, ADR-049, Dex→Keycloak) delivery plan; platform is now on **v3** (`XEnvironment`, ADR-067) — two model generations on. — **Evidence:** `gitops/tenant-claims` gone; `gitops/environments`/`products`/`teams` live; `v3-implementation-plan.md` + archived `v3-cutover.md` exist. — **Recommended fix:** "Superseded by v3 (ADR-067)" banner + archive.

## docs/plans/tenant-api-v2-cutover.md

- [SEVERITY: medium] **Describes a v1→v2 cutover entirely superseded by v3, no banner.** "Status: FINALIZED — ready to execute" reads live; live model is v3 (`XEnvironment` v1alpha3, `restrict-environment-envelope`). — **Recommended fix:** "Superseded — v1→v2→v3" banner + archive.

## docs/plans/v3-implementation-plan.md

- [SEVERITY: medium] **Completed build plan still written forward-looking, no DONE markers.** Every stream (F1, L2a/b/c, L3a/b/c, P4) described as to-build; v3 is LIVE. The companion `docs/archive/v3-cutover.md` (correctly archived, ✅ table) shows this plan's work shipped. — **Recommended fix:** "Status: DELIVERED — v3 live (see archive/v3-cutover.md)" header + move to `docs/archive/`.
- [SEVERITY: low] Naming/ECR/Pod-IAM/policy mappings match the live v3 scheme — accurate.

## docs/archive/v3-cutover.md

- [SEVERITY: low] **Correctly archived and honestly framed** — historical cutover record with a ✅/⛔/TODO build-status table; the few TODO items are rebuild-time steps. — **Recommended fix:** none (optional one-line "v3 is now live" top-note).

## docs/compliance/scp-control-mapping.md

- [SEVERITY: high] **"Exempt Role Governance" is factually wrong and would misdirect an auditor.** States the live config sets **"three" exempt roles** and instructs auditors to "flag any expansion beyond these three." Live config sets **seven** (adds `crossplane-ecr-provisioner`, `crossplane-provisioner-*`, `platform-use1-eks-karpenter-*`, `preprod-use1-eks-karpenter-*`). — **Evidence:** live `exempt_roles` in `organizations/terragrunt.hcl`. — **Recommended fix:** update to all seven (with per-wildcard justification) and re-bless the baseline.
- [SEVERITY: medium] **Attachment Summary stale vs live (claims deployed controls but shows module defaults).** Table (63-72) lists `require-tagging`/`restrict-iam-users` on **Workloads** only; live attaches them to **Platform too** (security-audit fix). Header advertises "Live configuration." — **Recommended fix:** add the live Platform attachments (or relabel "module defaults"); bump "Last reviewed: 2026-06-01."
- [SEVERITY: low] SCP names, SIDs, denied actions all verified accurate against `scps.tf`; `required_tags` + allowed regions match `variables.tf`.

## docs/examples/compliant-deployment.yaml

- [SEVERITY: medium] **The "scaffolder emits the same shape" claim is now inaccurate (Deployment vs Rollout).** Header line 4 says the scaffolder emits the same shape; the skeleton now emits `kind: Rollout` (argoproj.io/v1alpha1, ADR-056), not `kind: Deployment`. — **Evidence:** `scaffolder/templates/new-product/skeleton/k8s/base/` renders `kind: Rollout` with `strategy.canary`. — **Recommended fix:** reword to "the scaffolder emits the same compliant shape as an Argo **Rollout** (ADR-056); this Deployment form is the minimal equivalent," or add a sibling Rollout example.
- [SEVERITY: low] **The example itself passes the current Kyverno policy set** — product-scoped ECR image (platform acct 829808296602), explicit immutable tag, cpu+mem requests AND limits, liveness AND readiness probes, named SA, no IRSA annotation, no Service; namespace `acme-store-dev` (dev → replica-floor N/A; replicas:2 anyway). Compliant.

---

## Cross-cutting note

Of the 11 plans, **6 are completed/superseded work still living as if active** and should move to `docs/archive/` (or gain a dated DONE/Superseded banner): `085-workload-availability-defaults.md`, `131-slsa-build-l3.md`, `adr-071-digest-promotion-implementation.md`, `v3-implementation-plan.md`, `tenant-api-v2-and-identity-delivery.md`, `tenant-api-v2-cutover.md`. The two v2 tenant-API plans are two model-generations stale. `slsa-l3-provenance-cutover-HANDOFF.md` explicitly says it "can be deleted once P4 lands" — P4 landed, so it's delete-ready. By contrast `056` and `080` are the gold standard (completed work + dated status in place); `102` is honestly mid-flight but carries dead `teams.hcl`/`/tenant`-label framing.

The two highest-impact factual errors are both in the **compliance doc** (`scp-control-mapping.md`): the exempt-role count (3 claimed vs 7 live) and the SCP attachment summary lagging the live OU-coverage fix — material in an auditor artifact, even though the SCP/SID mappings themselves are accurate. `compliant-deployment.yaml` still admits cleanly but mis-claims parity with a scaffolder that now emits Rollouts. No broken intra-repo cross-links found.
