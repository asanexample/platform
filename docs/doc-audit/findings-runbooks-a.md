# Documentation Audit — docs/runbooks/ (batch A: 20 runbooks)

Checkout: `/Users/josh/centric/platform/.claude/worktrees/doc-audit` @ origin/main. Clusters parked; verification against repo only.

## docs/runbooks/add-aws-account.md

- [SEVERITY: medium] SCP-exemption block (lines 66-70) stale on count and content — repo has **7** entries and Karpenter exemptions are anchored per-cluster (`platform-use1-eks-karpenter-*`, `preprod-use1-eks-karpenter-*`), not leading-wildcard `*-karpenter-*` (a security audit explicitly rejected the wildcard). — **Evidence:** runbook 66-70 vs `infra/live/aws/mgmt/global/organizations/terragrunt.hcl:23-32` — **Recommended fix:** list all 7 actual entries; replace `*-karpenter-*` with the two anchored names.
- [SEVERITY: medium] OU table says Platform OU "Gets `protect-data-and-network` SCP" (line 56) — actually attaches `protect-data-and-network`, `require-tagging`, `restrict-iam-users`. — **Evidence:** `terragrunt.hcl:38-42` — **Recommended fix:** list all three.
- [SEVERITY: medium] Step 4 (line 230) names baseline modules `cloudtrail`, `config`, `guardduty-member` — only `cloudtrail` exists. — **Evidence:** `ls infra/modules/aws/` — **Recommended fix:** drop the non-existent module names.
- [SEVERITY: medium] FAQ rename command `aws organizations update-account --name` (line 361) is not a real AWS CLI command (no `UpdateAccount` API). — **Recommended fix:** remove fabricated command; describe member-account rename path.
- [SEVERITY: medium] `accounts` map example (83-90) hardcodes emails, omits SOPS `account_emails[...]` (ADR-066) convention; stated lowercase naming (line 96) contradicts the Capitalized live keys (`Platform`, `Test`, …) where `name = each.key`. — **Evidence:** `terragrunt.hcl:52-57`, `organizations/main.tf:93` — **Recommended fix:** show the SOPS accessor; reconcile naming convention.
- [SEVERITY: low] Verified correct: `scp-control-mapping.md`/`modify-scps.md` links, root SCP list, `close_on_deletion=false`, OU map, wrong-OU `parent_id` update.

## docs/runbooks/incident-scp-blocking.md

- [SEVERITY: high] Step 3a `exempt_roles` editable block (162-174), labeled "Keep ALL six live entries — do NOT drop these," is wrong: 7 live entries exist and it includes the security-audit-rejected `*-karpenter-*` wildcard while dropping an anchored entry. A responder copy-pasting during an incident would broaden the Karpenter exemption org-wide and regress an audited control. — **Evidence:** runbook 162-174 vs `organizations/terragrunt.hcl:23-32` — **Recommended fix:** replace with the 7 actual entries; correct "six".
- [SEVERITY: low] SCP→error table accurate; optionally add 4 missing SIDs (`ProtectAccessAnalyzer`, `DenyDisableEbsDefault`, `DenyUnencryptedRdsCluster`, `ProtectKmsKeys`).
- [SEVERITY: low] Verified correct: `scps.tf` path, Option-A `ArnNotLike` condition pattern, cross-links, deny-regions resolution.

## docs/runbooks/arc-github-app.md

Accurate and current. Secret name/keys, `arc-github-app`/`arc-runners`, `platform-infra` scale set, repo-scoped install, ADR-065, Pod-Identity SA all verified.

- [SEVERITY: low] Step 2 `gh api /orgs/.../installations` (line 36) needs org-admin scope, unstated. — **Recommended fix:** note the required scope.

## docs/runbooks/argocd-sso.md

Correctly marked **Legacy**; historical Dex+SAML→Identity Center described accurately; cross-links resolve.

- [SEVERITY: low] "Fix: Verify `dex_enabled = true`" (166) is opposite of current (`dex_enabled = false`), but the legacy banner covers it. — **Recommended fix:** optional inline "(legacy)" note.

## docs/runbooks/dex-sso.md

- [SEVERITY: medium] Banner claims "both `dex` and `oauth2-proxy` units/modules are gone" — FALSE for oauth2-proxy: module still exists, now fronts the Argo Rollouts dashboard SSO (only removed from Backstage). — **Evidence:** `infra/modules/oauth2-proxy/` exists; `infra/live/aws/platform/us-east-1/platform/rollouts-sso/terragrunt.hcl:102`; correct wording at `docs/architecture/identity-and-sso.md:8` — **Recommended fix:** reword to clarify only the `dex` module is gone and oauth2-proxy persists.
- [SEVERITY: low] `dex` module genuinely removed; body otherwise accurate as history.

## docs/runbooks/identity-sso-troubleshooting.md

Accurate and complete (current-state doc). Keycloak issuer/redirects, `argocd-cli` PKCE client, RBAC mappings, ExternalSecret paths, seed users, gateway svc all verified.

- [SEVERITY: low] §3 comment references `host_aliases[].ip`, a field that doesn't exist; the unit input is `oidc_gateway_alias_host`. — **Evidence:** `infra/live/.../backstage/terragrunt.hcl:146` — **Recommended fix:** reference `oidc_gateway_alias_host`.

## docs/runbooks/debug-argocd-sync.md

- [SEVERITY: high] The entire "ApplicationSet PR-preview generator failures" section (123-150) describes functionality that does not exist on v3 — per-PR previews (ADR-032) are not implemented; the v2 surface (`github_org`, `preview_appset`, `tokenRef`, `preview=true`) was removed at cutover. No `pullRequest` generator anywhere; named artifacts are fictional; misattributed to ADR-069. — **Evidence:** `infra/modules/argocd-apps/README.md:5,124`; `grep -rn pullRequest infra/ gitops/` → nothing — **Recommended fix:** delete the section or replace with the per-stage `preview_domain` host-rewrite; note ADR-032 is future work.
- [SEVERITY: medium] AppProjects are per-**Product** (`product-<key>`, e.g. `product-alpha-demo`), not per-team; example `argocd proj get alpha` / `kubectl get appproject alpha` target a non-existent project. — **Evidence:** `argocd-apps/delivery.tf:32` — **Recommended fix:** correct to `product-<team>-<product>`.
- [SEVERITY: medium] Whitelist presented as complete omits `Rollout`/`AnalysisTemplate`/`AnalysisRun` which ARE whitelisted (ADR-056). — **Evidence:** `delivery.tf:53-55` — **Recommended fix:** add the three `argoproj.io` kinds.
- [SEVERITY: medium] §6 calls XEnvironment sync a "per-Product ApplicationSet"; it's a single registry-sync `Application` named `environments` recursing `gitops/environments`. — **Evidence:** `delivery.tf:228,263-298` — **Recommended fix:** describe as the single `environments` app.
- [SEVERITY: medium] §6 jsonpath command targets the wrong object twice (XEnvironment isn't its own Application; `ignoreDifferences` is a global argocd-cm customization, not an Application `.spec` field — returns empty), and contradicts the doc's own line 185. — **Evidence:** `infra/live/.../argocd/terragrunt.hcl:225-227` — **Recommended fix:** inspect argocd-cm instead.
- [SEVERITY: low] App-name inconsistency (`alpha-demo` vs `alpha-demo-dev`); cross-links all resolve.

## docs/runbooks/backstage-argocd.md

Accurate and complete. Read-only account/RBAC, `argocd_account_token` hook, secret path, in-cluster URL, admin-secret fallback all verified.

## docs/runbooks/backstage-github-app.md

Largely accurate.

- [SEVERITY: low] Install-repo example stale — omits `alpha-conformance` (`gitops/products/alpha/conformance.yaml:14`). "Last reviewed: 2026-06-03" is oldest of the four. — **Recommended fix:** add the product or derive from `gitops/products/`; refresh date.

## docs/runbooks/backstage-scaffolder-github-app.md

- [SEVERITY: medium] Cites a non-existent ADR section — `ADR-067 §"New Product lifecycle"` (line 50). ADR-067 has no such heading; the write-App flow is ADR-062 §5. — **Evidence:** `grep -nE '^#{1,4} ' docs/adrs/067-idp-domain-model.md`; `docs/adrs/062-...:93` — **Recommended fix:** point at ADR-062 §5. Template dir itself exists.
- [SEVERITY: low] Mild "disjoint installations" tension under New-Product elevation (resolved via config-order precedence). — **Recommended fix:** note disjointness is the base-posture invariant.

## docs/runbooks/github-ownership-app.md

Accurate. Secret shape `{app_id, installation_id, pem}`, permissions, org install, `gitops/products/` derivation, ADR-072 Flavor A all verified.

- [SEVERITY: low] "alpha/bravo org teams created" (line 10) stale — `gitops/teams/platform.yaml` now adds a third (platform) team. — **Recommended fix:** "alpha/bravo/platform" or "one per `gitops/teams/`".

## docs/runbooks/environment-onboarding.md

Well-grounded; XRD shape, cluster names, role/policy naming, unit paths all verified. The #647 caveat is correct (Composition emits only the in-cluster RoleBinding).

- [SEVERITY: low] Line 47 calls the rendered policy "per-Product `restrict-images`"; it's authored per-environment (`restrict-images-<ns>`), as line 324 correctly states. — **Evidence:** `composition.yaml:827` — **Recommended fix:** reword line 47.

## docs/runbooks/environment-deprovisioning.md

ECR `deletionPolicy: Orphan`, quota-zeroing, gate decommission-exclusion all confirmed.

- [SEVERITY: medium] Procedure (54-55) says the decommission PR "automerges," contradicting its own model table (line 17) and the gate, which requires a human approval (≠ author). — **Evidence:** `.github/scripts/gitops-gate/detect-lifecycle-decommission.sh:1-8`, `publish-verdict.sh:175-181` — **Recommended fix:** change to "not auto-merged — requires a reviewer approval."

## docs/runbooks/environment-aws-access-pod-identity.md

Accurate and complete. policyStatements shape, role naming, permissions boundary, `allow-pod-identity-egress` CNP, IRSA-annotation rejection all verified. No issues.

## docs/runbooks/app-supply-chain-onboarding.md

Accurate. ECR push role, platform account ID, verify-images/attestations policy names + registry derivation, all cross-links and ADR refs verified. (`build-sign.yml`/`slsa-provenance.yml` live in external `asanexample/trusted-ci`, unverifiable here but consistent.) No issues.

## docs/runbooks/gitops-gate-automerge.md

v2 runbook with v3 banner, but checks/testing not fully reconciled to live v3 scripts:

- [SEVERITY: medium] Check #6 cites stale `spec.apps.*`; v3 uses `spec.services.*`. — **Evidence:** `xenvironment-xrd.yaml:133-163`; `validate-environments.sh:97` — **Recommended fix:** `spec.apps.*`→`spec.services.*`.
- [SEVERITY: medium] Local-testing command (160-162) passes env vars (`CHANGED_FILES`, `BOT_AUTHOR`, `RENDER_CHECK`) the script never reads — silent false-green. — **Evidence:** `validate-environments.sh:10-28` reads `BASE_DIR`/`HEAD_DIR`/`ENVIRONMENT_FILES`/`IAM_SENSITIVE` — **Recommended fix:** use the real vars.
- [SEVERITY: medium] Check #8 (aggregate quota sum + `MAX_TENANTS_PER_TEAM`=10) not implemented in v3 gate. — **Evidence:** no such logic/var in `.github/scripts/gitops-gate/*.sh` — **Recommended fix:** drop or relabel as v2-only/future.
- [SEVERITY: low] Check #7 `requested-by` not gate-enforced; "(not New Environment)" parenthetical likely stale "(not New Tenant)" leftover; retired check name "Environment Claims Gate" (line 127) vs updated `gitops Gate`/`gitops Approval`. — **Recommended fix:** reconcile to v3 names. (Script inventory at 163-164 all exists and is correct.)

## docs/runbooks/eks-cluster-access.md

- [SEVERITY: medium] Developer namespace-scoped kubectl Steps (137-153) describe `aws eks update-kubeconfig --role-arn .../DeveloperAccess-<team>` as a working flow, but that role is the #647 gap (not provisioned); the caveat is buried after the procedure (165-168), so a top-down reader fails at `update-kubeconfig`. — **Evidence:** CLAUDE.md IAM table; `deploy-app-preprod.md` handles this correctly — **Recommended fix:** move #647 note to the top; direct to `platctl kubeconfig`.
- [SEVERITY: low] Otherwise accurate: cluster names, PlatformAdmin pattern, SSM tunnel, break-glass, eks-tunnel.sh usage, cross-links all verified.

## docs/runbooks/cluster-scale-down-up.md

- [SEVERITY: medium] Break-glass manual scale-UP (58-60) says `terragrunt apply` recreates the Karpenter NodePool — it won't: `platctl down` deletes only the NodePool CR via kubectl, so a plain apply reports 0 changes and autoscaling stays dead. `platctl up` uses `-replace=helm_release.nodepool[0]`. — **Evidence:** `cmd/platctl/internal/cli/scale.go:147-152` — **Recommended fix:** use `terragrunt apply -replace=helm_release.nodepool[0]`.
- [SEVERITY: medium] Manual scale-DOWN (28-31) does `kubectl delete nodepool --all` then immediately zeroes the system group — but delete returns before NodeClaims/instances terminate, orphaning them; the supported path also clears `do-not-disrupt`, waits for NodeClaims gone, and deletes the EC2NodeClass. — **Evidence:** `scale.go:488-535` (esp. comment 517-520) — **Recommended fix:** add a "wait until `kubectl get nodeclaims` empty" step or steer strongly to `platctl down`.
- [SEVERITY: medium] Undocumented: `platctl down` stops the SSM bastion (`up` restarts it), undercutting failure-mode #7's "reach the cluster via SSM tunnel since Tailscale is down" — the bastion is off after a park. — **Evidence:** `scale.go:62-66,116-122,684-707` — **Recommended fix:** document bastion stop/start; note the tunnel needs the bastion running.
- [SEVERITY: low] Node-group restore table, Tailscale namespace, eks-tunnel repoint verified. `platctl up` "~3-5 min" optimistic (can wait ~15 min, `scale.go:204-215`).

## docs/runbooks/debug-ingress-and-dns.md

Accurate and current. Shared `preprod-gateway`/`default`, GatewayClass `cilium`, `sectionName: https`, wildcard cert/ClusterIssuer, all CiliumNetworkPolicy names, ingress-identity-8 explanation, cross-links all verified. No issues.

## docs/runbooks/deploy-app-preprod.md

- [SEVERITY: medium] ECR push role name stale (per-team) — lines 347, 479 use `github-actions-ecr-push-alpha` ("Per-team … ADR-036, #60"), but roles are now per-**Product**: `github-actions-ecr-push-product-<product>` (ADR-069 §5). — **Evidence:** `infra/live/aws/platform/us-east-1/platform/github-oidc/terragrunt.hcl:30-44` — **Recommended fix:** correct name and re-attribute to ADR-069.
- [SEVERITY: low] Line 75 uses bare `platctl kubeconfig` (not on PATH; built to `./bin/platctl`). `--env` flag is correct. — **Recommended fix:** use `./bin/platctl`.
- [SEVERITY: low] Everything else verified: ResourceQuota, LimitRange/NetworkPolicy, Gateway, `letsencrypt-prod`, copied TLS secret, AppProject allow-list, ADR refs, cross-links.

---

## Cross-cutting note

- **Two high-severity copy-paste hazards:** the SCP `exempt_roles` block in `incident-scp-blocking.md` (would regress an audited control org-wide during an incident), and the fictional PR-preview section in `debug-argocd-sync.md` (sends operators chasing non-existent v2 generators). Both trace to v3 cutover (ADR-067/069) + SCP security-audit hardening not propagated to runbooks.
- **Recurring stale theme — per-team → per-Product:** ECR push roles (`deploy-app-preprod.md`, `add-aws-account.md`), AppProjects (`debug-argocd-sync.md`), team enumerations (`backstage-github-app.md`, `github-ownership-app.md`) all reflect the retired per-team / two-team (`alpha`/`bravo`) model. Ground truth is registry-derived per-Product from `gitops/products/` and now three teams (alpha/bravo/platform).
- **`spec.apps.*` → `spec.services.*`** XRD rename missed in `gitops-gate-automerge.md`; grep all docs for `spec.apps`.
- **platctl break-glass gap:** `cluster-scale-down-up.md` is the weakest operationally — manual fallbacks diverge from what `platctl` actually does (NodePool `-replace`, NodeClaim drain wait, bastion power).
- **Strongest docs (no fixes):** `arc-github-app.md`, `backstage-argocd.md`, `identity-sso-troubleshooting.md`, `environment-aws-access-pod-identity.md`, `app-supply-chain-onboarding.md`, `debug-ingress-and-dns.md`.
