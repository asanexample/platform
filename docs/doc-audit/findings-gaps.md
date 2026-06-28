# Documentation Audit — GAP HUNT (undocumented / thinly-documented shipped features)

Checkout @ origin/main. Clusters parked; verification against repo only. This pass is orthogonal to the per-file accuracy waves: it diffs **what shipped** (recent commits, the live module set, `gitops/`, CI, scaffolder) against the docs to find features with **no or thin** documentation. Severity = centrality × risk.

Recurring framing: **the recent work has excellent ADRs and registry READMEs, but the *operator runbook* / *house skill* layer ("how do I actually do this") is where the holes are.**

---

## Domain: Identity, access & the agent platform

### GAP: Authoring / operating a platform agent (XAgent) — HIGH

- **Shipped:** a whole agent control plane — `gitops/agents/triage-copilot.yaml` (live XAgent claim), `infra/modules/crossplane/charts/agent-api/` + `.../charts/agent-policies/` (**both no README**), `argocd-apps/agents.tf` (per-agent ApplicationSet), the admission gate `.github/scripts/gitops-gate/validate-agents.sh`, ADRs 074/080/082/086. Triage copilot is live + autonomous on the hub.
- **Doc status:** ADR-only + a good `gitops/agents/README.md`; the two charts have **no README**; **no** house skill, **no** runbook, **no** architecture doc on authoring/operating an agent; no `new-agent` scaffolder template.
- **Recommended:** an **`authoring-platform-agents` house skill** (write the XAgent claim, supply-chain/Product join, `obsRead`/`autonomy`/`model` knobs, kill-switch `lifecycle.phase: suspended`, what `validate-agents.sh` + `restrict-agent-envelope` reject, per-agent ApplicationSet delivery) + a `docs/runbooks/agent-operations.md`. **Single biggest hole** — a new agent grants cluster-read + Bedrock + a Pod-Identity role and the author has no guide.

### GAP: Keycloak admin-plane break-glass procedure (ADR-087) — HIGH

- **Shipped:** sealed bootstrap-admin secret (#941), master-realm passkey flow (#930/#935), ADR-087. Standing admin is now passkey-MFA with a *sealed* break-glass bootstrap-admin.
- **Doc status:** ADR-087 (decision) + scattered architecture mentions. **No runbook** (`docs/runbooks/` has `kyverno-break-glass.md` but nothing for the Keycloak admin plane).
- **Recommended:** `docs/runbooks/keycloak-break-glass.md` — where the sealed secret lives, how to unseal/use it when passkey-SSO admin login is unavailable, how to re-seal/rotate after. A sealed break-glass credential with no recovery runbook is the classic "the one time you need it, it's undocumented" trap.

### GAP: `platform-directory` module — MEDIUM-HIGH

- **Shipped:** `infra/modules/platform-directory/` — the platform-infra Postgres (CNPG) identity directory (#862, ADR-084 Phase 1).
- **Doc status:** **No README**, zero references in `docs/`/skills; only home is ADR-084.
- **Recommended:** at minimum a module README (purpose, the `declared`→`proven` handle-trust tiers, schema, consumers, backup posture). The directory is the runtime "who" the owner-routing/identity model resolves against.

### GAP: People lifecycle — onboard / offboard a person — MEDIUM

- **Shipped:** `gitops/people/` (#886), `gitops/roles/` (#887), the IC generator (#888) + Keycloak roster→users generator (#889), Backstage onboard-person/offboard-person templates (#890/#912/#914).
- **Doc status:** **Partial but scattered** — strong registry READMEs + the strategy doc, but **no single operations runbook** and no `docs/runbooks/` joiner/leaver entry.
- **Recommended:** `docs/runbooks/manage-people.md` — joiner/mover/leaver end-to-end: which template, what PR, who approves, and **what actually changes on apply** (esp. what is/isn't revoked on offboard).

### GAP: Temporary-power / JIT elevation + `platctl access` (ADR-088) — MEDIUM (HIGH per cross-cutting)

- **Shipped:** `platctl access list` (#943) / `access check` (#945) — `cmd/platctl/internal/cli/access.go` — the read-side eligibility resolver over `gitops/people × gitops/roles`; break-glass eligibility (#946). ADR-088.
- **Doc status:** ADR + strategy doc; the **`platctl` skill does NOT mention the `access` command group**. No runbook.
- **Recommended:** add an **`access`** section to the **`platctl` skill** (list/check, standing-vs-borrowable model). A full "how to borrow elevated access" runbook is premature (grant/revoke/activation "land later" per the code) — document the read-side now, flag the activation runbook as a follow-up.

### GAP: PagerDuty on-call module operations (ADR-084 Phase 2) — LOW-MEDIUM

- **Shipped:** `infra/modules/pagerduty/` (#932; schedule v1↔v2 churn #942/#944/#947).
- **Doc status:** module README + `pagerduty-identity-handoff.md` (the identity *contract*), but no operations doc (adding/editing a schedule/escalation policy; the v1-vs-v2 `pagerduty_schedule` resource gotcha that caused the revert).
- **Recommended:** a short ops section in the README or an on-call runbook.

---

## Domain: Delivery, progressive delivery & supply chain

> **Adequately documented (do NOT re-document):** Argo Rollouts / progressive delivery (the `docs/guides/zero-downtime/` suite + `zero-downtime-deployments.md` + `rollout-and-gate-operations.md`); blue-green vs canary selection; the `argo-rollouts` module README; Release/digest promotion (`promote-a-release.md` + `promotion-and-release.md`); supply-chain CI (`app-supply-chain-onboarding.md`, `supply-chain-incidents.md`, `supply-chain-overview.md`, the skill); the gitops Gate (`gitops-gate-automerge.md`); deprovision-environment/product runbooks.

### GAP: oauth2-proxy as a reusable Keycloak-SSO front — HIGH

- **Shipped:** `infra/modules/oauth2-proxy/` (helm_release, ExternalSecret from an SM OIDC-client-secret key, generated cookie secret, gateway-Service lookup, `issuer_host_alias` split-horizon, `allowed_groups`/`email_domains` gate). First consumer: the `rollouts-sso` unit (#919) fronting the Argo Rollouts UI. Explicitly designed as a generic front for any no-native-auth UI.
- **Doc status:** **none** for the capability — module has **no README**, and there is **no runbook/how-to** for the end-to-end pattern (mint an OIDC client in keycloak-config → wire the SM-key ExternalSecret → point a gateway-config HTTPRoute at the proxy Service → handle the hub split-horizon `issuer_host_alias`). Only worked example is inline HCL in `rollouts-sso`.
- **Aggravating:** `docs/runbooks/identity-sso-troubleshooting.md:7-8` actively says *"Dex and oauth2-proxy were retired"* — now **wrong**; oauth2-proxy was re-introduced for the Rollouts UI. (Also `docs/README.md` says oauth2-proxy is retired — same error.)
- **Recommended:** module README (on the list) + a `docs/runbooks/sso-front-a-ui.md` (or a section in `architecture/identity-and-sso.md`) with `rollouts-sso` as the reference; correct the two "retired" claims.

### GAP: New Resource self-service cloud resources (ADR-073) — MEDIUM-HIGH

- **Shipped (built, not just merged):** `scaffolder/templates/new-resource/template.yaml` ("New Resource" — S3/SQS/SNS/DynamoDB → `spec.services.<svc>.resources.<name>` via gated PR); live Composition support (`.environment-api-tests/environments/resources-s3-dev.yaml`, `.kyverno-tests/environment-envelope/values-resources-s3.yaml`); the gate validates against the Team envelope `allowedEngines`/per-env count.
- **Doc status:** **thin / scattered** — only ADR-073 + a one-line envelope-cap mention in the `environment-onboarding` skill. No developer runbook for "declare a cloud resource on my Service" end-to-end. (Note: contradicts the stale "ADR-073 MERGED (not built)" memory — it IS built.)
- **Recommended:** `docs/runbooks/new-resource.md` (or a section in `environment-onboarding`/`ship-a-service.md`): engine→kind derivation, the `allowedEngines`/count envelope, how access lands on the Pod-Identity role, where connection coordinates surface (the `<svc>-resources` ConfigMap).

### GAP: New Product per-language golden starters — LOW

- **Shipped:** `scaffolder/templates/new-product/` ships six runtime skeletons (go/java/nodejs/python/ruby/rust), selected via the `language` enum.
- **Doc status:** thin — only the template enum/descriptions; `ship-a-service.md` doesn't mention language choice.
- **Recommended:** a short "supported runtimes / what the golden starter gives you" section.

---

## Domain: Observability, cost, elasticity & foundation

### GAP: `infra/docs/17-available-modules.md` — the canonical module catalog is badly stale — HIGH

- **Shipped:** the file (linked from `docs/README.md` as "Catalog of all infrastructure modules") omits, by grep: `karpenter`, `keycloak`, `backstage`, `cloudnative-pg`, `opencost`, `pagerduty`, `platform-directory`, and 15 of 17 observability modules — all live.
- **Recommended:** regenerate the catalog from the actual `infra/modules/` tree (CLAUDE.md's list is more current and can seed it).

### GAP: Per-app SLOs (`app_slos` → Mimir-ruler burn-rate rules) — MODERATE

- **Shipped:** `observability-mimir` `app_slos` → an `app-slos` ruler namespace, registry-derived per prod claim (#900/#882, ADR-056 Phase 3).
- **Doc status:** scattered — only as the canary freeze-gate input; absent from `observability-current-state.md`, the `observability-authoring` skill (covers only Sloth SLOs), and the Mimir README.
- **Recommended:** a "Per-app SLOs (registry-derived)" section in `observability-authoring` and/or `observability-current-state.md`.

### GAP: Karpenter day-2 operations — MODERATE

- **Shipped:** `aws/karpenter` + units both clusters (ADR-078 Phase 1 live); `platctl validate` diagnoses Karpenter readiness.
- **Doc status:** scattered — ADR (decision) + README + the park-drain bit in `cluster-scale-down-up.md`. No Karpenter ops runbook/architecture doc.
- **Recommended:** `docs/runbooks/karpenter-operations.md` — NodePool/EC2NodeClass tuning, consolidation/disruption, interruption handling, "pods Pending / no nodes" debugging, the park-drain ordering.

### GAP: CloudNative-PG capability + backup/restore — MODERATE

- **Shipped:** `cloudnative-pg` backs Backstage + the new `platform-directory` Postgres.
- **Doc status:** README + ADR mentions only. `infra/docs/16-disaster-recovery.md:46-70` explicitly flags CNPG DBs as running with **no backup configured** — gap acknowledged but unaddressed operationally.
- **Recommended:** a "Platform databases (CloudNative-PG)" note + a backup/restore runbook (Barman/object-store).

### GAP: OpenCost / cost management — MODERATE

- **Shipped:** `observability-opencost` + a hub `opencost` unit (ADR-079 P11 pt1 live).
- **Doc status:** thin — `infra/docs/19-cost-management.md` mentions OpenCost **0 times** (covers only tags + structural levers; "monitoring & governance = planned").
- **Recommended:** update `19-cost-management.md` to reference the live OpenCost (cluster/namespace allocation, the `platform-cost.json` dashboard) + a short usage runbook; note CUR→Athena (P11 pt2) still outstanding.

### GAP: Logs & traces spoke onboarding — MODERATE

- **Shipped:** preprod `observability-logs-spoke` + `observability-traces-spoke` (#625); Loki/Tempo modules have `spoke_ingest` inputs.
- **Doc status:** thin — `observability-spoke-onboarding.md` is titled "(metrics)" and only covers the prometheus-agent spoke.
- **Recommended:** extend the spoke-onboarding runbook with logs (Alloy) and traces (OTel) spoke sections + their hub Loki/Tempo ingest edges.

### GAP: `observability-current-state.md` omits cloud-resource metrics / OpenCost / per-app SLOs; Mimir ruler thin — LOW-MODERATE

- **Shipped:** P5a CloudWatch datasource, P5b YACE, OpenCost, `app_slos`, the ruler rules-sync cron + `spoke_ingest` edges — all live.
- **Recommended:** add "Cloud-resource observability (P5a/P5b)", "Cost (OpenCost)", "Per-app SLOs", and a ruler/rules-sync note so the as-built doc matches deployment.

---

## Cross-cutting (completeness critic)

### GAP: Three canonical inventories all stale by the same 5 modules — HIGH

`CLAUDE.md` module list, `infra/docs/17-available-modules.md`, and (for two of them) the module README are ALL missing: `argo-rollouts`, `oauth2-proxy`, `pagerduty`, `platform-directory`, `aws/cost-allocation-tags`. — **Recommended:** add all five to CLAUDE.md + regenerate the catalog; add the two missing READMEs.

### GAP: `platctl access` (ADR-088 JIT elevation) undocumented — HIGH

Absent from the platctl skill command tree and all docs; privileged-access tooling. — **Recommended:** add an `access` row + how-to to the platctl skill.

### GAP: `docs/README.md` says "oauth2-proxy is retired" while the module is live + in use — HIGH

Actively wrong in the doc index (and in `identity-sso-troubleshooting.md`). — **Recommended:** correct both.

### GAP: New identity registries missing from the canonical `CLAUDE.md` map — MEDIUM

`gitops/people`, `gitops/roles`, `gitops/grants`, `gitops/agents` each have a local README but are absent from CLAUDE.md's "registries-as-single-source" paragraph (which lists only teams/products/environments). (`gitops/grants/` is a documented stub — no grant files yet.) — **Recommended:** extend the CLAUDE.md registries paragraph + the domain-model doc.

### GAP: ADR-087 Keycloak temp-admin & the W11 error-budget freeze gate are named-but-unbacked — MEDIUM

`docs/README.md` advertises "error-budget freeze" with no how-to behind it (commit `e8cfe82e`); ADR-087 temp-admin has no doc outside the ADR. — **Recommended:** document the freeze gate in `rollout-and-gate-operations.md`; add the temp-admin to the Keycloak break-glass runbook above.

### GAP: doc-map / cross-link integrity — MEDIUM

- `docs/README.md` is a curated spotlight, not a complete index: **28 of ~42 runbooks** and several architecture docs aren't individually listed, and there is **no `docs/runbooks/README.md` or `docs/architecture/README.md`** index. Discovery depends on directory browsing.
- **Orphan architecture docs** (exist, never linked from the index, zero inbound cross-links): `identity-and-access-strategy.md` (the ADR-086 north-star — most significant), `kyverno-shift-left.md`, `pagerduty-identity-handoff.md`, `crossplane-environment-api.md` (linked from CLAUDE.md but not the index), `tenant-api-v2.md` (superseded; file not flagged).
- **Recommended:** add per-directory README indexes (or expand the main index); link the four live orphans; mark `tenant-api-v2.md` superseded.

### GAP: people-gate / roles-gate machinery undocumented — LOW

The PR gates enforcing the People/roles registries (`b1d09273`/`310241cb`) have 0 doc hits, whereas gitops-gate/auto-promote are documented. — **Recommended:** extend `gitops-gate-automerge.md` to cover them.

### GAP: no house-skills index / ADR→code→runbook map in user-facing docs — LOW-MEDIUM

The 16 skills are listed only in CLAUDE.md; nothing in `docs/` indexes them or ties decision → code → operations. — **Recommended:** a "Skills & where decisions live" page.

---

## Top gaps overall (prioritized for the next pass)

1. **Authoring/operating a platform agent** — no skill, no runbook, no arch doc, 2 README-less charts. (HIGH)
2. **Three canonical inventories stale by 5 modules** + the two missing module READMEs (oauth2-proxy, platform-directory). (HIGH)
3. **`docs/README.md`/`identity-sso-troubleshooting.md` say oauth2-proxy is retired — it's live + in use.** (HIGH)
4. **`platctl access` (JIT elevation) absent from its skill + all docs.** (HIGH)
5. **Keycloak admin-plane break-glass runbook** (sealed bootstrap-admin, ADR-087). (HIGH)
6. **oauth2-proxy reusable SSO-front how-to.** (HIGH)
7. **New Resource self-service (ADR-073) developer runbook** — built, ADR-only doc. (MEDIUM-HIGH)
8. **`infra/docs/17-available-modules.md` regenerate.** (HIGH)
9. **manage-people joiner/leaver runbook.** (MEDIUM)
10. **Observability later-phase gaps** (per-app SLOs, Karpenter day-2, CNPG backup, OpenCost/cost, logs/traces spokes). (MEDIUM)
11. **Doc-map: per-directory indexes + link the orphan architecture docs.** (MEDIUM)
