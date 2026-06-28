# ADR Accuracy Review — ADRs 067–077

Checkout: `/Users/josh/centric/platform-adr-review` (worktree at origin/main).

---

## ADR-067: IDP Domain Model — Team / Product / Service / Environment / Customer

- **Status quoted:** `Accepted (built + live, v3 model 2026-06-11) — the north-star conceptual model ... The current platform is an explicit **degenerate instance** of it.`
- **Findings:**
  - [SEVERITY: low] Status accurate and well-framed. v3 model live: `gitops/products/`, `gitops/environments/`, `gitops/teams/` exist; `gitops/tenant-claims/` gone. — **Evidence:** `gitops/products/{alpha,platform}`, `gitops/environments/alpha/{shop,checkout,conformance}`, `ls gitops/tenant-claims` → absent. — **Proposed fix:** none.
  - [SEVERITY: low] §8 "Implemented (#377/#501) — release-keyed ApplicationSet, auto ≤ staging reconciler, gated-prod release-approver" VERIFIED. — **Evidence:** `gitops/teams/alpha.yaml:15` `releaseApprover`; `infra/modules/argocd-apps/delivery.tf:2`.
  - [SEVERITY: low] Referenced architecture docs all exist. — **Proposed fix:** none.
- **Decision concerns:** none — explicitly north-star; "degenerate instance" framing sound.

## ADR-068: Product-Scoped & Cross-Team Access Model

- **Status quoted:** `Proposed — ... **Refines ADR-053** ... **Rebuild-gated** for implementation ... vocabulary and the data-contract are adopted now.`
- **Findings:**
  - [SEVERITY: low] §7 release-approver "Implemented (#501)" callout accurate even though the ADR is Proposed (only that sub-part is built). — **Evidence:** `gitops/roles/team-admin.yaml`, `gitops/teams/*.yaml` carry `releaseApprover`.
  - [SEVERITY: medium] §Context (line 12 chain diagram) + §6 present `Dev-<team> → DeveloperAccess-<team> IAM role → EKS access entry → team-<team>:developers → RoleBinding` as the "whole live chain" today. Per CLAUDE.md `DeveloperAccess-<team>` is **NOT currently provisioned** (#647) — the chain is partly aspirational, not current. — **Evidence:** CLAUDE.md IAM Roles table. — **Proposed fix:** qualify §Context/§6 that the IAM-role/access-entry hops aren't provisioned today (#647).
  - [SEVERITY: low] `gitops/grants/` exists but is a shell (only README) — consistent with the Proposed/CRD-shell status. — **Evidence:** `ls gitops/grants` → README only.
- **Decision concerns:** §6 OIDC-native cluster-auth cutover (retiring `DeveloperAccess-<team>` as the kubectl vehicle) is presented as decided but rebuild-gated/unbuilt; confirm alignment with the #647→#364 cluster-access direction.

## ADR-069: Delivery Source-of-Truth — Product Registry + Environment Claims

- **Status quoted:** `Accepted — built + live; **refines ADR-061.** ... **Rebuild-gated** for implementation; the contract is the platform-domain-api.md normative schema.`
- **Findings:**
  - [SEVERITY: medium] **Self-contradictory header + stale body.** Status says "built + live," yet line 9 says "**Rebuild-gated** for implementation" and Consequences (line 136) say "All ride the rebuild, not in-place." The decision IS built and live, so the rebuild-gated/future-tense language is stale and misleading. — **Evidence:** `069:5` "built + live" vs `:9` "Rebuild-gated" and `:136`; `infra/modules/argocd-apps/delivery.tf:2`. — **Proposed fix:** strike "Rebuild-gated for implementation" + the "ride the rebuild" framing; convert future-tense decision text to past/present, or add an "as-built" note (additive v3 cutover 2026-06-11).
  - [SEVERITY: low] §5 "the `github-oidc` unit `fileset`s the Product registry and mints one OIDC role per Product" VERIFIED at the live unit. — **Evidence:** `infra/live/aws/platform/us-east-1/platform/github-oidc/terragrunt.hcl:34-43,91-165`.
  - [SEVERITY: low] §3/§6 (per-Product `ApplicationSet`, registry-sync) present in `delivery.tf`. — **Evidence:** `delivery.tf:225-231`.
- **Decision concerns:** none on decision quality; the issue is stale "not yet built" framing in an Accepted-built-live ADR.

## ADR-070: Tenant Application Config & Secrets

- **Status quoted:** `Proposed — a **new platform capability**. ... **Rebuild-gated** for the deep wiring; the **schema reservation** lands in F1 so the XEnvironment shape is complete.`
- **Findings:**
  - [SEVERITY: low] §6 "Schema (lands in F1): reserve `services.<svc>.config`/`secrets` … now" — the reservation has **already landed** in the XRD. Future-tense "lands in F1" mildly stale but harmless. — **Evidence:** `crossplane/charts/environment-api/templates/xenvironment-xrd.yaml:187-201` `config`/`secrets` blocks marked "Reserved (ADR-070) … Inert until the secrets paved-road ships." — **Proposed fix:** optionally note the reservation is merged; realization pending.
  - [SEVERITY: low] "Composition mints **no** per-tenant secret store" consistent with the inert XRD block.
- **Decision concerns:** Sound; "reveal is gated+audited, not hidden" well argued and bounded.

## ADR-071: Image-Digest Promotion via the Control Plane

- **Status quoted:** `Accepted + **IMPLEMENTED & PROVEN LIVE** (2026-06-15) — the full chain works end-to-end on app-alpha-shop ...`
- **Findings:**
  - [SEVERITY: low] Status VERIFIED. `kind: Release` records exist with the exact schema/example shown. — **Evidence:** `gitops/releases/alpha/shop/{dev,prod}.yaml` (`apiVersion: platform.refplat.org/v1beta1`, `environmentRef`, per-service `digest`).
  - [SEVERITY: low] §3 ApplicationSet reads digest from `gitops/releases/…`; release-keyed-generator (#377) matches `delivery.tf`. — **Evidence:** `delivery.tf:69-96`.
- **Decision concerns:** none — exemplary implementation record.

## ADR-072: App-Repo Naming & Team Ownership

- **Status quoted:** `Accepted — **Flavor A** (drop the app- prefix; GitHub org Teams for ownership) is the near-term decision. **Flavor B** ... deferred ...`
- **Findings:**
  - [SEVERITY: medium] Stale present-tense: line 36 "**GitHub org Teams are not used today** — team identity flows through Keycloak groups … and the repo-name prefix." Flavor A (the `github-teams` unit) is **built and live** (#532), so org Teams ARE now used. — **Evidence:** `infra/modules/github-teams/`; `infra/live/aws/platform/us-east-1/platform/github-teams/terragrunt.hcl:21-30`; CLAUDE.md. — **Proposed fix:** update line 36 to past tense + an "as-built" note that Flavor A landed.
  - [SEVERITY: low] Internal tension: line 38 "existing demo app repos (`app-alpha`, `app-bravo`)" vs line 62 "zero app repos today." — **Proposed fix:** clarify line 62 as "zero app repos under the new naming."
- **Decision concerns:** none — Flavor A vs B split well reasoned.

## ADR-073: Self-Service Cloud Resources (the resource paved road)

- **Status quoted:** `Accepted (2026-06-17)`
- **Findings:**
  - [SEVERITY: medium] **Inaccurate current-state claim.** §Security: "(Today's `crossplane-provisioner` role is ECR-only; widen it deliberately.)" The role is **not** ECR-only today — it already carries `iam:CreateRole` (IAM mgmt scoped by an `environment-role` name-prefix) + a deny-escalation boundary. — **Evidence:** `crossplane/main.tf:468` (`crossplane-provisioner-${cluster}`), `:494-495` boundary, `:515-542` grants `ecr:*` **and** `iam:CreateRole`, `:14` name-prefix scope; live `provider_services = ["ecr","iam","eks"]`. — **Proposed fix:** reword to "today manages ECR + the environment IAM roles (name-prefix-scoped, boundary-capped); widen under the same discipline."
  - [SEVERITY: low] Quoted reserved-block comment paraphrased/stale — actual XRD comment now "…(ADR-067 §7, **activated by ADR-073**)…" and the `kind` enum includes `keyvalue`. — **Evidence:** `xenvironment-xrd.yaml:202-235`. — **Proposed fix:** refresh the quoted snippet/enum or mark illustrative.
- **Decision concerns:** Abstraction-above/safety-below framing strong; only risk is the ECR-only baseline error feeding an over-scoped "widen the role."

## ADR-074: Agentic Workloads — a Governed Platform for Running AI Agents

- **Status quoted:** `Proposed (2026-06-18)`
- **Findings:**
  - [SEVERITY: medium] Stale "first agent" framing, overtaken by reality + already corrected in ADR-076. §"Tier-0: the first reference agent" asserts the resource agent (ADR-075) is the first reference agent; in fact the **triage agent (ADR-080/082) is the first agent** — live + autonomous since 2026-06-26 — and ADR-076's amendment re-anchors tier-0 to triage. ADR-074 not updated. — **Evidence:** `076:12-16`; README `ADR-082 ... built + live 2026-06-26`. — **Proposed fix:** add an amendment that the triage agent became the de-facto first agent and `XAgent` runtime is built (ADR-082).
  - [SEVERITY: low] §71/§76 leave Agent-CRD-vs-`XAgent` as open; ADR-082 has since decided it (the `XAgent` composite, built). — **Proposed fix:** optional forward-pointer to ADR-082.
  - [SEVERITY: low] Spike 2/3 research artifacts not verifiable from repo. — **NEEDS OWNER VERIFICATION** if challenged.
- **Decision concerns:** Candid "Honest limits & open gaps"; predates/doesn't reference ADR-082 or ADR-076's correction.

## ADR-075: The Resource Agent — Conversational Self-Service (ADR-073 Phase B)

- **Status quoted:** `Proposed (2026-06-18)`
- **Findings:**
  - [SEVERITY: low] Refers to "**the existing** `platform:add-service-resource` scaffolder action (`backstage/.../addServiceResource.ts`)" as already existing. That action is ADR-073 Phase A (not built; app is in a separate repo), so it almost certainly doesn't exist yet. — **Evidence:** no `addServiceResource*` in this repo. — **Proposed fix:** qualify as "the (Phase-A) action, in the Backstage app repo."
  - [SEVERITY: low] Same "tier-0 = first agent" staleness as ADR-074. — **Proposed fix:** cross-note as in ADR-074.
- **Decision concerns:** Honest about modest standalone value; no quality concern.

## ADR-076: Agent / GenAI Observability

- **Status quoted:** `Accepted (2026-06-18; corrected 2026-06-27)`
- **Findings:**
  - [SEVERITY: low] The 2026-06-27 amendment is accurate and well done (backbone LIVE P1–P7; triage agent live tier-0 producer; withdraws the "sampled Tempo trace = audit record" claim). Matches memory. — **Evidence:** `076:5-46`.
  - [SEVERITY: low] By house append-only rule the un-amended **body** still contradicts the amendment (§Context line 60 "backbone is unbuilt"; Dependencies line 169; Consequences 180-181). The amendment flags it supersedes those sections. — **Proposed fix:** optional inline "(superseded — see amendment)" markers on D2/D6/Dependencies.
- **Decision concerns:** none — model of honest in-place amendment.

## ADR-077: Application Instrumentation Strategy

- **Status quoted:** `Accepted — Beyla eBPF baseline (P7a) + OTel Operator auto-inject (P7b) implemented + live; SDK / golden-path templates (P14) outstanding (2026-06-22)`
- **Findings:**
  - [SEVERITY: low] Status consistent: `observability-beyla` + `observability-otel-operator` modules exist; memory records P1–P7 live. — **Evidence:** modules present. — **NEEDS LIVE VERIFICATION** of the actual Beyla DaemonSet + `Instrumentation` CR deployment.
  - [SEVERITY: low] D6 content-rule cross-ref to ADR-076 consistent. — **Evidence:** `077:82-86` ↔ `076:126-143`.
- **Decision concerns:** none — clear layered decision.

---

## Cross-cutting note

Dominant theme: **stale "not-yet-built / rides-the-rebuild" framing surviving into ADRs whose decisions shipped — additively, not via the planned rebuild those ADRs assumed.** ADR-069 carries a literally self-contradictory header ("built + live" + "Rebuild-gated"); ADR-072 says org Teams "are not used today" while `github-teams` is live; ADR-074/075 still call the resource agent the "first agent" when triage (ADR-080/082) beat it to production — a staleness ADR-076 already corrected for itself but the sibling agentic ADRs didn't inherit. Secondary theme: **current-state baseline claims that don't match the code** (ADR-073's "crossplane-provisioner role is ECR-only", contradicted by its existing `iam:CreateRole` + boundary). Recommend a sweep to (a) reconcile each Accepted ADR's body tense with its real built/live status, and (b) re-verify "today the platform does X" baselines against the modules.
