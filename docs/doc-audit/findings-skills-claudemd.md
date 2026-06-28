# Documentation Audit — house skills + CLAUDE.md

Checkout @ origin/main. Clusters parked; verification against repo only. (Vendored `terraform-skill/` out of scope.)

## CLAUDE.md (root)

- [SEVERITY: high] Replica-floor described as **Audit** but it is now **Enforce** on both live clusters (#934). Line 239: "Currently Audit (rolling to Enforce, issue #844)". — **Evidence:** both live policy units set `replica_floor_failure_action = "Enforce"`; commit `a58ff22d`/#934. — **Fix:** "Enforce on preprod + platform — a single-replica `*-prod` workload is now rejected at admission; lower stages may stay at 1." Drop "#844 rolling."
- [SEVERITY: high] ArgoCD SSO stale. Line 197: "Dex + SAML bridge to AWS Identity Center … SSO config injected via `argocd_cm_extra`." Dex retired; ArgoCD now brokers OIDC directly through Keycloak. — **Evidence:** `argocd/variables.tf:141` (`dex_enabled` default false); live unit `argocd/terragrunt.hcl:176,82-91,233-244`. — **Fix:** "direct Keycloak OIDC (Dex retired, ADR-053/059); runs after keycloak-config; client secret via External Secrets."
- [SEVERITY: medium] Module inventory (line 7) omits four shipped shared modules: `argo-rollouts`, `oauth2-proxy`, `pagerduty`, `platform-directory`. — **Fix:** add them.
- [SEVERITY: medium] AWS module inventory (line 8) omits `cost-allocation-tags`. — **Fix:** add it.
- [SEVERITY: medium] House Skills list (16-29) omits `cluster-parking` and `skill-self-correction` (both exist + load-bearing). — **Fix:** add both.
- [SEVERITY: low] Architecture-decisions section (189-204) has no entry for Argo Rollouts (ADR-056), oauth2-proxy SSO front, or per-team PagerDuty (ADR-084). — **Fix:** add brief bullets.
- Verified correct: Terragrunt hierarchy + SOPS section, deployment-ordering DAG, `run --all`/`hcl fmt` (v1.x), destroy invocation, IAM table incl. #647 gap, private-EKS/Tailscale norm, Kyverno required/mutated lists (other than replica-floor).

## .claude/skills/terraform-style/SKILL.md

- [SEVERITY: high] Claims `versions.tf` exists "only when the module uses a non-AWS provider" — false; all 67 module dirs ship a `versions.tf`. An author would wrongly omit it from a new AWS-only module. — **Evidence:** SKILL.md:37,53,247 vs `find infra/modules -name versions.tf | wc -l` = 67. — **Fix:** state every module has a `versions.tf`; a non-AWS provider merely adds a `required_providers` entry.
- [SEVERITY: medium] Provider-constraint style misstated: prescribes floor ranges `>= 5.0`, but house norm is pessimistic `~> MAJOR.0` and aws is on **v6**. — **Evidence:** SKILL.md:39,107-121 vs `~> 6.0`/`~> 3.0` across modules. — **Fix:** document `~> 6.0` pessimistic constraints; bump the example off v5.

## .claude/skills/terragrunt-units/SKILL.md

- [SEVERITY: low] `--filter-allow-destroy` (line 192) is a no-op without `--filter`; skill doesn't note the caveat. — **Fix:** optional cross-note. Otherwise accurate.

## .claude/skills/apply-and-destroy/SKILL.md — accurate

## .claude/skills/cluster-access/SKILL.md — accurate

## .claude/skills/cluster-parking/SKILL.md — accurate

## .claude/skills/crossplane-composition-authoring/SKILL.md — accurate

## .claude/skills/supply-chain-onboarding/SKILL.md — accurate

## .claude/skills/skill-self-correction/SKILL.md — accurate

## .claude/skills/platctl/SKILL.md

- [SEVERITY: medium] Commands table omits the `access` command (ADR-088): `platctl access list` / `access check <person> <role>`. — **Evidence:** `cmd/platctl/main.go:35`, `cmd/platctl/internal/cli/access.go:16-112`. — **Fix:** add an `access` row + subcommands.
- [SEVERITY: low] `.platctl.yaml` is gitignored (copy from `.platctl.yaml.example`); global `--config <path>` flag not mentioned.

## .claude/skills/environment-onboarding/SKILL.md

- [SEVERITY: medium] Step 3 overstates CODEOWNERS as the gate on an environment-claim PR; there is no CODEOWNERS entry for `gitops/environments/` (envelope-bounded claims are deliberately self-service). — **Evidence:** `.github/CODEOWNERS:1-44`; SKILL.md:57. — **Fix:** state the gate is the gitops Gate required status check (`validate-environments.sh`) + Kyverno `restrict-environment-envelope` admission, not a CODEOWNERS review.

## .claude/skills/authoring-k8s-workloads/SKILL.md

- [SEVERITY: high] `require-prod-replica-floor` described as "Audit today, Enforce later" (line 72) — now Enforce on both clusters (#934); a `<2`-replica `*-prod` workload is rejected. — **Evidence:** the two policy units (Enforce) + `git show a58ff22d`. — **Fix:** state Enforce on preprod + platform; module default remains Audit for fresh clusters.
- [SEVERITY: medium] Auto-injected `team` label derivation wrong: claims `alpha-demo-dev → team: alpha`, but the mutate rule uses `split(namespace,'-')[1]` = `demo` (the product). **Latent module bug** masked by a v2 test fixture (`namespace: team-alpha`). — **Evidence:** SKILL.md:46 vs `policies-chart/templates/mutate-workload-labels.yaml:33` + `.kyverno-tests/resources/mutate-input.yaml:8`. — **Fix:** file a module-bug (index `[1]`→`[0]` for v3 naming + fix fixture); meanwhile don't assert a value the module doesn't produce.
- [SEVERITY: low] Excluded-namespace list names `falco`/`observability` which aren't in the actual `excludeNamespaces`. verify-images/verify-attestations now Enforce on platform too.

## .claude/skills/kyverno-policy-authoring/SKILL.md

- [SEVERITY: medium] Uses replica-floor as the live "soaking in Audit under an Enforce cluster" exemplar (90-92); both live clusters promoted it to Enforce (#934). — **Fix:** note the soak is complete / pick a still-Audit example.

## .claude/skills/authoring-adrs/SKILL.md

- [SEVERITY: medium] Calls `081` the "latest" ADR (line 105); latest is now `088`. — **Fix:** point at a current ADR or drop "(latest)".

## .claude/skills/argocd-app-delivery/SKILL.md

- [SEVERITY: high] Claims the `argocd-cm` ignoreDifferences is "still keyed to v2 `XTenant` … an `XEnvironment`-scoped customization is currently missing" (137-142) — false; it shipped. — **Evidence:** `argocd/terragrunt.hcl:225` defines `...ignoreDifferences.platform.refplat.org_XEnvironment` (renamed from `_XTenant` at v3 cutover). — **Fix:** replace with a note that it's correctly keyed to `XEnvironment`; drop the "missing" warning.
- [SEVERITY: high] Says the XAgent Composition / agent delivery is "not yet in `infra/`/`gitops/`, design intent" and cites ADR-080 — wrong on all counts; it shipped (ADR-082, live 2026-06-26). — **Evidence:** `crossplane/charts/agent-api/files/composition.yaml`, `argocd-apps/agents.tf`, `gitops/agents/triage-copilot.yaml`, `docs/adrs/082-...md`. — **Fix:** rewrite to describe the shipped hub-targeted `agents.tf` registry-sync + workload ApplicationSet; cite ADR-082.
- [SEVERITY: low] gitops layout (41-49) omits `gitops/agents/`, `gitops/people/`, `gitops/roles/`.

## .claude/skills/observability-authoring/SKILL.md

- [SEVERITY: low] Gap: the shipped `pagerduty` module (per-team on-call, ADR-084) isn't referenced; skill covers only the single global PagerDuty receiver. Layer-1 OTel SDK inject presented as available today; `Instrumentation` CR lands with P14.

## .claude/skills/backstage-portal/SKILL.md

- [SEVERITY: medium] Scaffolder-template list (91-94) presented as exhaustive but omits `onboard-person/` and `offboard-person/` (back `gitops/people/`). — **Evidence:** `ls scaffolder/templates/`. — **Fix:** add both.

---

## Cross-cutting note

The dominant failure mode is **lag behind very recent flips/ships**, not structural rot: (1) the replica-floor Audit→Enforce flip (#934, yesterday) is stale in CLAUDE.md, `authoring-k8s-workloads` (HIGH — would get a prod manifest unexpectedly rejected), and `kyverno-policy-authoring`; (2) Dex retirement → direct Keycloak OIDC is stale only in CLAUDE.md. Two HIGH "not yet shipped" claims in `argocd-app-delivery` (XEnvironment ignoreDifferences; XAgent/ADR-082) describe in-repo, live capabilities as future intent — these mis-route an agent into "build it" when it exists. The terraform-style `versions.tf` claim is the one purely-structural HIGH. No `run-all`/`hclfmt`, Tenant/`teams.hcl`, or bare-IRSA drift survives in any skill. One latent **module bug** surfaced: the `team`-label mutate injects the product token, not the team, for v3 namespaces (file independently of the doc fix).

### CLAUDE.md drift items (most load-bearing file)

1. [HIGH] Replica-floor still "Audit (rolling to Enforce, #844)" — now **Enforce** both clusters (#934). Line 239.
2. [HIGH] ArgoCD SSO still "Dex + SAML bridge" — now **direct Keycloak OIDC**, Dex retired. Line 197.
3. [MEDIUM] Shared-module inventory missing argo-rollouts, oauth2-proxy, pagerduty, platform-directory. Line 7.
4. [MEDIUM] AWS-module inventory missing cost-allocation-tags. Line 8.
5. [MEDIUM] House Skills list missing cluster-parking + skill-self-correction. Lines 16-29.
6. [LOW] No architecture-decision bullet for Argo Rollouts (ADR-056), oauth2-proxy, or per-team PagerDuty (ADR-084).
