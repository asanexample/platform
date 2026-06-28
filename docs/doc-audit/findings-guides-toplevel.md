# Documentation Audit — docs/guides/zero-downtime/ + docs top-level

Checkout: `/Users/josh/centric/platform/.claude/worktrees/doc-audit` @ origin/main. Clusters parked; verification against repo only.

> The zero-downtime directory contains **11** files (not 7); the extras (README.md, reference-automatic-vs-yours.md, troubleshooting-developers.md, tutorial-first-deploy.md) were also audited.

## docs/guides/zero-downtime/demo-walkthrough.md

- [SEVERITY: low] Verified accurate. Rollout name `app-<team>-<product>`, namespace `<team>-<product>-prod`, freeze query `slo:current_burn_rate:ratio{sloth_id="<ns>-availability"}` and gate `>= 0.95` / `< 2` match the scaffolder prod overlay. Standalone `AnalysisRun` demo manifests carry no image → pass Kyverno. — **Recommended fix:** none.

## docs/guides/zero-downtime/faq.md

- [SEVERITY: low] Accurate. All in-page anchors resolve. Replica-floor "rejects < 2 at admission" now correct (Enforce, #934). Hostname `rollouts.preprod.aws.refplat.org` confirmed. — **Recommended fix:** none.

## docs/guides/zero-downtime/glossary.md

- [SEVERITY: low] Accurate and consistent with the policy chart: preStop 10s, `terminationGracePeriodSeconds: 30`, PDB `maxUnavailable: 1`, replica floor "(Enforced)". No drift vs the platform glossary (complementary). — **Recommended fix:** none.

## docs/guides/zero-downtime/how-to-extend-platform.md

- [SEVERITY: low] The worked flip example "Audit → Enforce (e.g. the replica floor)" is now historical: both live clusters already Enforce (#934). Procedure remains generically valid; "keep the module default Audit" note correct (default still `Audit`, `policy/variables.tf:191`). — **Recommended fix:** add a note that replica floor is already promoted, or pick a still-Audit policy as the example.
- [SEVERITY: low] All other references verified (toggle vars, chart template paths, `.kyverno-tests/`, `var.app_slos`, `app-slo-rules.yaml.tftpl`).

## docs/guides/zero-downtime/how-to-ship.md

- [SEVERITY: low] Accurate. Rollout name matches skeleton; hostname confirmed; abort-vs-revert GitOps guidance matches the `RespectIgnoreDifferences` wiring. — **Recommended fix:** none.

## docs/guides/zero-downtime/overview-developers.md

- [SEVERITY: low] Accurate. Injected/generated table matches the policy chart; Mermaid flow + two-gates framing match `progressive.yaml`. ADR-085 link resolves. — **Recommended fix:** none.

## docs/guides/zero-downtime/overview-platform.md

- [SEVERITY: low] Accurate/well-grounded: SleepAction "GA on k8s 1.35", `enable_rollout_kind` CRD-ordering caveat, `RespectIgnoreDifferences`, both rollouts hostnames, `#as-built-status` anchor all confirmed.
- [SEVERITY: low] Uses lowercase "tenant" ("tenant Application/manifests/prod apps") — pre-ADR-067 noun; glossary marks it deprecated for "environment". — **Recommended fix:** prefer "environment"/"app" (the Mimir "per-tenant" usages are legit).

## docs/guides/zero-downtime/README.md (index)

- [SEVERITY: low] Accurate. ADR-054/049 links resolve; per-stage strategy table matches the skeleton. — **Recommended fix:** none.

## docs/guides/zero-downtime/reference-automatic-vs-yours.md

- [SEVERITY: low] The "Injected/generated" table describes `securityContext` as "non-root hardened" — but the mutate injects only `allowPrivilegeEscalation:false`/`drop:[ALL]`/`seccompProfile:RuntimeDefault`; `runAsNonRoot`/`readOnlyRootFilesystem` are required only on regulated tiers, not auto-injected on `standard`. — **Recommended fix:** drop "non-root" from the standard-tier description.

## docs/guides/zero-downtime/tutorial-first-deploy.md

- [SEVERITY: low] Accurate. Rollout name, namespace, `Step: 1/5` canary shape, hostname all consistent with the skeleton/IaC. — **Recommended fix:** none.

## docs/guides/zero-downtime/troubleshooting-developers.md

- [SEVERITY: low] Accurate. fail-open `len(result)==0` semantics match `progressive.yaml`; rejection-policy table matches the Kyverno catalog. — **Recommended fix:** none.

## docs/README.md

- [SEVERITY: medium] Stale identity claim: "Dex **and oauth2-proxy** are retired." oauth2-proxy is **live** — it fronts the Argo Rollouts web UI SSO on both clusters via the `rollouts-sso` units. Only Dex (and oauth2-proxy *as the ArgoCD/Backstage/Grafana bridge*) is retired. — **Evidence:** `infra/live/aws/{platform,preprod}/us-east-1/platform/rollouts-sso/terragrunt.hcl`, `infra/modules/oauth2-proxy/`. — **Recommended fix:** "Dex is retired; oauth2-proxy is no longer the SSO bridge for ArgoCD/Backstage/Grafana (it still fronts the Rollouts UI)."
- [SEVERITY: low] Doc map verified complete/current: all 17 `architecture/*.md`, all 14 `runbooks/*.md`, Start-Here/Reference targets resolve. — **Recommended fix:** none.

## docs/glossary.md

- [SEVERITY: low] Accurate and ADR-067-current: "Tenant"/"Zone" carry explicit *(deprecated)*/*(retired)* markers; Environment/XEnvironment, Pod Identity, generated-host order `<product>-<team>-<stage>.<baseDomain>`, `team-<team>/<product>-<svc>` ECR all match the repo. — **Recommended fix:** optionally refresh "Last reviewed: 2026-06-12".

## docs/user-guide.md

- [SEVERITY: medium] Stale ECR repo path in the push example: `…/team-alpha/app:v1.0.0`. Current convention is `team-<team>/<product>-<svc>` (ADR-067), so `team-alpha/app` doesn't match any provisioned repo and is required by Kyverno `restrict-images` in enforced namespaces — a dev copy-pasting this pushes to a non-existent repo and the pod is admission-rejected. — **Evidence:** user-guide.md:770-771. — **Recommended fix:** use `team-alpha/shop-web:v1.0.0`.
- [SEVERITY: medium] `DeveloperAccess-<team>` presented as a usable role with no caveat, but it's **not currently provisioned** (#647). — **Evidence:** user-guide.md:651, CLAUDE.md IAM table. — **Recommended fix:** add the "NOT provisioned; use `platctl kubeconfig`/PlatformAdmin until #647" caveat.
- [SEVERITY: low] Account-count vs example mismatch: Step 2 expects "4 member accounts (…, **test**, …)" but every `accounts = {…}` example lists only platform/preprod/prod. — **Recommended fix:** include `test`.
- [SEVERITY: low] Otherwise accurate/current: Keycloak-OIDC ArgoCD SSO (Dex/SAML marked retired), `gitops/` registries as source-of-truth (`teams.hcl` retired), `platctl` flow.

## docs/ship-a-service.md

- [SEVERITY: medium] Prerequisite points devs at the `DeveloperAccess-<team>` role for kubectl, not currently provisioned (#647) — following it for cluster access fails. — **Evidence:** ship-a-service.md:19. — **Recommended fix:** note it's not yet provisioned; direct to `platctl kubeconfig`/PlatformAdmin. (Marked optional, which softens it.)
- [SEVERITY: low] Otherwise accurate: app repo `<team>-<product>` (no `app-` prefix) matches the scaffolder; Kyverno must-haves, PR-preview "not yet wired" caveat, gated-prod release-approver flow all current.

## Missing files

None. All four expected top-level files exist; all in-scope zero-downtime files exist (11 total).

---

## Cross-cutting note

The zero-downtime guide suite is unusually accurate — every command, manifest value (preStop 10s / grace 30s / PDB maxUnavailable:1 / gate 0.95 / freeze 2×), path, anchor, and hostname checked matches the repo, and replica-floor "Enforce" is correctly reflected (evidently updated alongside #934). Example workloads are admission-safe. The two recurring real problems are **outside** the zero-downtime suite, both from the `#647` `DeveloperAccess-<team>` regression and pre-ADR-067 naming: (1) `DeveloperAccess-<team>` documented as usable in `user-guide.md` + `ship-a-service.md` despite not being provisioned; (2) the stale ECR path `team-alpha/app` in `user-guide.md` no longer conforms to `team-<team>/<product>-<svc>` and would be Kyverno-rejected. The single doc-map inaccuracy is `docs/README.md`'s blanket "oauth2-proxy is retired", contradicted by the live `rollouts-sso` deployment the zero-downtime docs rely on. The two glossaries do not drift (deliberately partitioned; "Tenant"/"Zone" marked deprecated).
