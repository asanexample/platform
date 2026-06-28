# Documentation Audit — docs/runbooks/ (batch B: 22 runbooks)

Checkout: `/Users/josh/centric/platform/.claude/worktrees/doc-audit` @ origin/main. Clusters parked; verification against repo only.

## docs/runbooks/keycloak-sso.md

- [SEVERITY: medium] Stale Dex/ArgoCD framing — claims it "Mirrors the Dex setup (`dex-sso.md`)" and that Keycloak's IdC SAML app is "separate from Dex's and ArgoCD's". Dex is retired and ArgoCD consumes Keycloak OIDC directly (`dex_enabled = false`), so ArgoCD has no IdC SAML app. — **Evidence:** `argocd/terragrunt.hcl:176,82`; `dex-sso.md:3` ("REMOVED") — **Recommended fix:** drop the "separate from Dex's and ArgoCD's" parenthetical and the "Mirrors the Dex setup" pointer.
- [SEVERITY: medium] Wrong apply path / Tailscale prerequisite — claims `keycloak-config` applies via the Keycloak provider against `keycloak.aws.refplat.org` requiring Tailscale. It actually applies over an in-cluster port-forward to `http://localhost:18080` and does NOT need the tailnet. — **Evidence:** live `keycloak-config/terragrunt.hcl` start_pf hook + `url = "http://localhost:18080"`; `scripts/kc-portforward.sh` — **Recommended fix:** replace the Tailscale-to-apply claim with the port-forward path; keep Tailscale only for the browser verify step.
- [SEVERITY: medium] Points operators at bootstrap-only `secrets.hcl` for the two SSO secrets; canonical store is SOPS `secrets.enc.yaml` (values already there). — **Evidence:** `secrets.enc.yaml:18-19`; `common.hcl:27-28`; ADR-066 — **Recommended fix:** point to `sops` editing `secrets.enc.yaml`; note `secrets.hcl` is the `TG_SOPS_BOOTSTRAP` escape only.
- [SEVERITY: low] Compares cert format to retired `dex_sso_ca_data` secret. — **Recommended fix:** drop the Dex-secret name.
- Verified correct: ACS URL, SAML audience, `principal_type=SUBJECT`, `name_id_policy_format=Email`, the `openssl x509 | base64` command all match `keycloak-config/main.tf:148-172`.

## docs/runbooks/keycloak-upstream-idp.md

- [SEVERITY: medium] OIDC client-secret named wrong and not wired — presets say `upstream_oidc_client_secret in secrets.hcl`, but the secrets-file key is `keycloak_upstream_oidc_client_secret`, and nothing plumbs it (no `common.hcl` exposure, no unit input). OIDC path is documented-but-not-plumbed. — **Evidence:** `keycloak-config/variables.tf:84-89`; `secrets.hcl.example:47`; `common.hcl:26-28` — **Recommended fix:** use the secrets-file key name; note the OIDC path also needs `common.hcl`/`_base.hcl` to surface the secret and the unit to set the input (currently absent).
- [SEVERITY: medium] Same bootstrap-only `secrets.hcl` staleness across all preset annotations — should reference SOPS `secrets.enc.yaml` (ADR-066). — **Recommended fix:** reference `secrets.enc.yaml`.
- [SEVERITY: low] SAML preset uses `var.keycloak_sso_url` — in a unit these are `include.base.locals.keycloak_sso_url`. — **Recommended fix:** show the `include.base.locals.*` accessor or label as illustrative.
- Verified correct: the `upstream` object schema matches `variables.tf:41-63`; `sync_mode=FORCE`, per-team `ssoGroup` → `/<team>` mapper, ADR-059, provider endpoint URLs all check out.

## docs/runbooks/kyverno-break-glass.md

- [SEVERITY: medium] Calls the Kyverno ECR-read role an "IRSA role"; it is now bound via EKS Pod Identity (ADR-047/#594). — **Evidence:** doc line 86 vs `policy/main.tf:20,57,95,178`; `outputs.tf:22` — **Recommended fix:** "ECR-read role bound via EKS Pod Identity (ADR-047)".
- [SEVERITY: low] §2 walks an Audit→Enforce flip, but both clusters already Enforce (replica-floor flipped, #934); "Last reviewed 2026-05-29" predates current state. — **Recommended fix:** add "current state: Enforce on both clusters"; bump review date.
- Otherwise accurate: webhook config names, `failurePolicy` derivation, `exclude_principals`, ADR-014/040 links verified.

## docs/runbooks/supply-chain-incidents.md

- [SEVERITY: medium] §3 (org/repo rename) incomplete — tells operator to update only `trusted_ci_subject_regexp`, but there are TWO cluster-wide regexps and the one gating image signature + SBOM is the omitted `trusted_ci_build_subject_regexp`. A trusted-ci move updating only the former leaves signatures/SBOM failing. — **Evidence:** `policy/main.tf:169-170`; `policies-chart/values.yaml:87,95`; `verify-images-product.yaml:61` — **Recommended fix:** name both regexps in §3.
- [SEVERITY: low] §3 step 1 leads with `appSubjects`; the actual per-product gate for a repo rename is `spec.repo` (registry-derived); `appSubjects` is the unpopulated self-signing fallback. — **Recommended fix:** lead with "update the Product registry `spec.repo`".
- Verified correct: cosign `--certificate-identity-regexp` values, `github-actions-ecr-push-product-*`, all knob names, cross-links.

## docs/runbooks/promote-github-app.md

- [SEVERITY: low] Coverage gap — the `platform/promote/github-app` secret is also read by the in-repo `auto-promote.yml` reconciler via PlatformDeployer, not mentioned in Store/How-it-uses/Rotation. — **Evidence:** `.github/workflows/auto-promote.yml:32-37,57-68` — **Recommended fix:** note the platform-side reconciler as a second consumer.
- Otherwise accurate & complete: bot login `asanexample-promote[bot]`, per-Product OIDC grant, both gate scripts, ADR-071/062 links verified.

## docs/runbooks/observability-access.md

- [SEVERITY: low] "Shipped today" dashboard table omits `agent-triage.json` and `argo-rollouts.json` that exist in the module. — **Evidence:** `observability/dashboards/` — **Recommended fix:** add them or soften "Shipped today".
- Otherwise accurate: Keycloak OIDC login, admin secret keys, Mimir `X-Scope-OrgID: platform`, SNS account verified.

## docs/runbooks/observability-alerts.md

- [SEVERITY: medium] "SNS auth is IRSA + sigv4" — SNS publish is now EKS Pod Identity (ADR-047). — **Evidence:** `observability/main.tf:294,615` — **Recommended fix:** "EKS Pod Identity (ADR-047) + sigv4".
- Otherwise accurate: all 31 curated alert names map 1:1 to `alerts/curated.yaml`; secret mounts, severity routing, inhibit rule match.

## docs/runbooks/observability-instrumentation-verify.md

- [SEVERITY: low] `get cm beyla-config` references a CM name not verifiable offline (chart-generated). — **Recommended fix:** confirm actual CM name on a live cluster; low risk.
- Otherwise accurate: platform/preprod Beyla namespaces, Mimir limit 50, traces spoke host, `enable_instrumentation` verified.

## docs/runbooks/observability-spoke-onboarding.md

- [SEVERITY: low] "Add the next spoke" lists only `spoke_ingest.tenants` + `extra_tenant_datasources`; live config also sets `query_tenants`/`ruler_tenants` (needed for canary reads or hub-side ruler alerts). — **Evidence:** `platform/.../mimir/terragrunt.hcl:150,162` — **Recommended fix:** note them as optional.
- Otherwise accurate: HTTPRoute/CNP names, prometheus-agent inputs, all "Where it's defined" paths verified.

## docs/runbooks/observability-troubleshooting.md

- [SEVERITY: medium] Mimir "S3 / IRSA errors" section tells operator to check the `eks.amazonaws.com/role-arn` annotation on the `mimir` SA — under Pod Identity that annotation does NOT exist, misdirecting diagnosis. — **Evidence:** `observability-mimir/main.tf:21,312` — **Recommended fix:** retitle "S3 / Pod-Identity errors"; verify the Pod Identity association.
- Otherwise accurate: query-scheduler enabled, RF=1, kafka/ingest-storage disabled, SSE-S3 bucket, gp3 default SC, grafana CNP verified.

## docs/runbooks/platform-rebuild-from-scratch.md

- [SEVERITY: low] Stale mention of retired Dex in first-rebuild gotcha #2 ("keycloak/dex/tailscale fail with i/o timeout"), while the same doc declares Dex gone. — **Evidence:** line 122 vs 92-96 — **Recommended fix:** drop "dex".
- Otherwise accurate and unusually well-grounded: every platctl command/flag, config key, script, module hook, cross-link verified. (`docs/archive/v3-cutover.md` link correct.)

## docs/runbooks/mcp-servers.md

- Accurate and complete — matches `.mcp.json` exactly (two servers `grafana` + `aws-api`, both read-only). No issues.

## docs/runbooks/modify-scps.md

- [SEVERITY: medium] `exempt_roles` "current live value has SIX entries" is wrong — live has SEVEN, and Karpenter is two env-specific entries, not one `*-karpenter-*` wildcard. Copying verbatim broadens the live exemption. — **Evidence:** `organizations/terragrunt.hcl:28-32` — **Recommended fix:** SIX→SEVEN; replace the wildcard with the two anchored names.
- [SEVERITY: medium] Attachment-count helper snippet is broken — counts a hard-coded literal array, ignores `$target`, always prints "2 SCPs". — **Evidence:** lines 280-283 — **Recommended fix:** drive the count from the actual `scp_attachments` map, or remove.
- [SEVERITY: low] "Eight built-in SCPs … used automatically" overstates — only 7 created unless `enable_hipaa_scp = true`. — **Evidence:** `organizations/main.tf:23-39` — **Recommended fix:** note the 8th (HIPAA) is conditional.
- [SEVERITY: low] "Adjusting SCP Attachments" example shows module default, not the live Platform-OU value. — **Recommended fix:** label as module default or use live shape.
- [SEVERITY: low] Cosmetic: `local {` should be `locals {` (line 163).

## docs/runbooks/test-sandbox-account.md

- [SEVERITY: medium] §2 claims `DenyTeamTagTampering` exempts only three named roles; live statement exempts the full `exempt_role_arns` set PLUS AWS service-linked roles, and is scoped only to the `Team` tag key. — **Evidence:** `organizations/scps.tf:418-443` — **Recommended fix:** state the exempt set is `exempt_roles` + service-linked roles, scoped to the `Team` tag key.
- [SEVERITY: low] "not tag IAM/ECR/Secrets/EC2" is broader than the policy — only `Team`-tag mutations are denied. — **Recommended fix:** qualify as "the `Team` tag".
- Otherwise accurate: account ID, PlatformDeployer posture, terratest trust refs, bootstrap-override flow, cross-links verified.

## docs/runbooks/secret-rotation.md

- [SEVERITY: low] §6 "Checking Current Key Age" queries `NextRotationDate`, always null (no `aws_secretsmanager_secret_rotation` configured). — **Recommended fix:** drop `NextRotation` from the query or note it's empty.
- Otherwise accurate: all secret paths, ExternalSecret names, ADR-053/059 verified.

## docs/runbooks/secrets-management.md

- [SEVERITY: medium] Architecture claims ESO authenticates via IRSA throughout (diagram + prose); ESO migrated to EKS Pod Identity (ADR-047/#594). — **Evidence:** `external-secrets/main.tf:16-18,119-126`; `secret-stores/main.tf:24,49-50` — **Recommended fix:** rewrite the auth chain as Pod Identity.
- [SEVERITY: medium] "Verify IRSA configuration" debug step is actively wrong — tells operator to confirm the `eks.amazonaws.com/role-arn` annotation, absent under Pod Identity. — **Evidence:** lines 245-252 — **Recommended fix:** verify the Pod Identity association.
- [SEVERITY: low] "New App Team Secret" prereqs describe an IRSA-scoped SecretStore (hedged as not-yet-deployed). — **Recommended fix:** scope via Pod Identity when it lands.
- [SEVERITY: low] Architecture omits the `secret-stores` module that creates the ClusterSecretStores. — **Recommended fix:** mention `secret-stores` + the SSM store.

## docs/runbooks/tailscale-vpn.md

- [SEVERITY: low] `tailscale api delete device` (line 346) is not a real CLI subcommand. — **Recommended fix:** drop it or point to the admin console / HTTP API.
- Otherwise accurate: subnet route, split-DNS records, userspace mode, cluster name, chart 1.96.5, provider pin, `eks-cluster-access.md` cross-link verified.

## docs/runbooks/transit-gateway-operations.md

- [SEVERITY: medium] "Create the Spoke Unit" template references `dependency.networking.outputs.transit_subnet_ids`, which does not exist — networking exposes `subnet_ids` (the real spoke filters it by `regex("transit$", name)`). Copy-pasting fails. — **Evidence:** `aws/networking/outputs.tf`; preprod `transit-gateway/terragrunt.hcl` — **Recommended fix:** show the actual `for ... if can(regex("transit$", name))` filter.
- [SEVERITY: low] Verify commands mix `AWS_PROFILE=management`/`=preprod` for spoke reads; raw `aws` with `management` won't see preprod resources without role assumption. — **Recommended fix:** standardize spoke reads on `AWS_PROFILE=preprod`.
- Otherwise accurate: all TGW module variables, RAM share name, outputs, ADR-034/035 links verified.

## docs/runbooks/upgrade-procedures.md

- [SEVERITY: medium] Stale Terragrunt command `terragrunt hclfmt --check` (line 447); v1.x CLI is `terragrunt hcl fmt --check`. — **Evidence:** `.github/workflows/ci.yml:156`, `.githooks/pre-commit:25`, `CLAUDE.md:141` — **Recommended fix:** change to `terragrunt hcl fmt --check`.
- [SEVERITY: low] "kube-prometheus-stack runs only on the platform cluster" is incomplete — the same pin drives the preprod prometheus-agent spoke. — **Evidence:** preprod `observability-spoke/terragrunt.hcl:11,89` — **Recommended fix:** note the pin is shared.
- All version pins verified against `_versions.hcl`/`versions.tf`/`.tool-versions` (Cilium 1.19.4, ArgoCD 9.5.14, Kyverno 3.8.1, EKS default 1.35). EKS upgrade variable names and unit dirs verified.

## docs/runbooks/product-deprovisioning.md

- [SEVERITY: medium] Post-purge verify uses `kubectl get ns -l platform.refplat.org/environment` — a label set NOWHERE. The Composition labels namespaces team/product/stage. The selector returns empty regardless, giving a false "gone" confirmation. — **Evidence:** `composition.yaml:86-97`; `policies-chart/values.yaml:37` — **Recommended fix:** use `-l platform.refplat.org/product=<product>` or `kubectl get ns <team>-<product>-<stage>`.
- [SEVERITY: low] Cross-doc contradiction: this doc correctly says decommission is reviewer-merged, but `environment-deprovisioning.md:54` says it "automerges". — **Recommended fix:** fix line 54 of the sibling doc.
- Otherwise accurate: action enum, sanctioned branch/approval model, ECR Orphan, quota name, registry-reconcile, cross-link verified.

## docs/runbooks/promote-a-release.md

- [SEVERITY: medium] Omits that the operator must choose the target (to) stage — both the Backstage template and the app workflow require it. — **Evidence:** `request-promotion/template.yaml:29-35,58-66`; `new-product/skeleton/.github/workflows/promote.yml:21,27` — **Recommended fix:** state both *from* and *to* stage are selected.
- [SEVERITY: medium] Example prod PR title `promote: <team>-<product>-prod -> <digest>` is wrong — that's the commit message; the actual PR title carries service + stage transition, no digest. — **Evidence:** `request-promotion/template.yaml:124` vs `:127` — **Recommended fix:** `promote: <team>-<product>-prod <service> (staging→prod)`.
- Otherwise accurate: Release path/CR, auto-promote ladder (prod excluded), releaseApprover sourcing, bot name, all 7 cross-links verified.

## docs/runbooks/rollout-and-gate-operations.md

- [SEVERITY: medium] Query-path restart command uses two `-l` flags on the same label key (`component=query-frontend -l component=query-scheduler`) — AND-combined, matches zero pods, silently no-ops during an incident. — **Recommended fix:** use `-l 'app.kubernetes.io/component in (query-frontend,query-scheduler)'` or two commands.
- [SEVERITY: low] Warning that `component=gateway` "also matches mimir-store-gateway" is inaccurate (store-gateway's label is `store-gateway`). — **Recommended fix:** drop/reword.
- Verified correct: AnalysisTemplate names, fail-open-on-empty, ruler-sync CronJob, `RespectIgnoreDifferences`, `kubectl argo rollouts` commands. **`require-prod-replica-floor … Enforce` verification (line 97) is CORRECT** — both live units set `replica_floor_failure_action = "Enforce"`; CLAUDE.md/memory claiming it's still Audit is the stale party, not the runbook.

---

## Cross-cutting note

1. **IRSA → Pod Identity drift is the dominant defect (ADR-047/#594).** Stale "IRSA" framing recurs as wrong/active-misdirection across `kyverno-break-glass.md` (ECR role), `observability-alerts.md` (SNS), `observability-troubleshooting.md` (Mimir S3), and most seriously `secrets-management.md` (ESO auth chain + an actively-wrong debug step). The modules are fully migrated; the docs lag. The `policy/variables.tf` descriptions also carry the stale term (out of doc scope, worth a follow-up).
2. **`secrets.hcl` vs SOPS `secrets.enc.yaml` (ADR-066).** Both Keycloak runbooks (and `secrets.hcl.example`) still send operators to the bootstrap-only plaintext file instead of the committed SOPS store.
3. **Retired-Dex residue.** Lingering mentions in `keycloak-sso.md`, `keycloak-upstream-idp.md`, `platform-rebuild-from-scratch.md`.
4. **Copy-paste-will-fail commands (highest operational risk):** `product-deprovisioning.md` (bogus `platform.refplat.org/environment` selector → false "gone"), `rollout-and-gate-operations.md` (double-`-l` same-key → zero pods), `transit-gateway-operations.md` (non-existent `transit_subnet_ids` output), `modify-scps.md` (hard-coded count snippet always "2").
5. **Live config outgrew the docs:** `modify-scps.md`/`test-sandbox-account.md` understate `exempt_roles`/`DenyTeamTagTampering` (now 7 + service-linked).
6. **Memory itself is stale on replica-floor** — the runbook correctly documents Enforce (#934); CLAUDE.md/MEMORY still say Audit/#844-deferred.
7. Cleanest: `platform-rebuild-from-scratch.md`, `mcp-servers.md`, `secret-rotation.md`, `tailscale-vpn.md`. All cross-links across all 22 files resolve.
