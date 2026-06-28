# Documentation Audit — docs/architecture/ (21 files)

Checkout: `/Users/josh/centric/platform/.claude/worktrees/doc-audit` @ origin/main. Clusters parked; verification against repo only.

## docs/architecture/identity-and-access-strategy.md

- [SEVERITY: medium] Built registries described as forward-looking. §2.4 calls `gitops/people/*.yaml` "(new — the missing piece)" and `AccessGrant` "(designed, ADR-068)"; §5 roadmap step 1 says "add `gitops/people/`"; "Related" calls it "the proposed `gitops/people/`" — but they exist. — **Evidence:** lines 157, 159, 444, 498 vs `gitops/people/{alpha-dev,bravo-dev,josh}.yaml` (#886), `gitops/roles/` 7 files (#887), `gitops/grants/README.md`. — **Fix:** re-tag as built.
- [SEVERITY: medium] Claims IC + Keycloak rosters are still hand-maintained HCL ("the live gap"). Both generators now derive from `gitops/people`×`gitops/roles`. — **Evidence:** `keycloak-config/terragrunt.hcl:69,185`; `mgmt/.../identity-center/terragrunt.hcl:23-24,59`. — **Fix:** "roster-derived generators wired (#888/#889); HCL no longer source of truth."
- [SEVERITY: medium] §2.3 / roadmap step 3 describe temporary-power activation with no ADR; ADR-088 now exists plus a `platctl access` command group. — **Evidence:** `docs/adrs/088-...md`, `cmd/platctl/internal/cli/access.go:18-26`. — **Fix:** cross-reference ADR-088.
- [SEVERITY: low] §2.3 shows `platctl elevate`; no such command (built command is `platctl access`, read-only). — **Fix:** use `platctl access` or mark unbuilt.
- [SEVERITY: low] §3.1 auth-strength items shown as design are partly implemented; ADR-087 exists, uncited. — **Fix:** note landed (#885/#899, ADR-087).

## docs/architecture/identity-and-sso.md

- [SEVERITY: high] Developer-access role names wrong: doc says `environment-operate`/`environment-view`; deployed `keycloak-config` emits `tenant-operate`/`tenant-view`. An engineer keying RBAC off the `roles` claim uses the wrong string. — **Evidence:** lines 56, 117-118, 126 vs `keycloak-config/main.tf:31` (`posture_roles = ["tenant-operate","tenant-view"]`), :323, :386-393. — **Fix:** use `tenant-*` (rename not yet applied), or add a "tenant-* today" note.
- [SEVERITY: medium] "Add a person" stale: says create in Keycloak admin UI; the live unit generates realm users from `gitops/people` (a UI user wouldn't be reconciled). — **Evidence:** `keycloak-config/terragrunt.hcl:181-185`. — **Fix:** "Add a `Person` file to `gitops/people/`."
- [SEVERITY: medium] Line 57 says seed users "derived from the git-native `Team` CRs" — users now come from `gitops/people` (Team CRs drive groups/roles only). — **Fix:** distinguish groups/roles (Team CRs) from users (people roster).
- [SEVERITY: medium] Lists Backstage RBAC (#197) as "⏳ future" but the #197 permission policy is referenced as live. — **Evidence:** `backstage/terragrunt.hcl:181-182`. — **Fix:** mark #197 shipped.
- [SEVERITY: low] Verified-correct: `dex_enabled=false`, oauth2-proxy retirement narrative, `argocd-cli` PKCE client, `scripts/kc-portforward.sh`, all links resolve.

## docs/architecture/pagerduty-identity-handoff.md

- Accurate and complete. Verified `infra/modules/pagerduty/` resources, the `external_identity(provider='pagerduty')` ADR-084 contract, `gitops/people/`, the bootstrap-users-swap framing; all cross-links resolve.

## docs/architecture/aws-organizations.md

- [SEVERITY: high] Platform OU SCP set understated → wrong effective count. Doc shows Platform OU = `protect-data-and-network` only (1 SCP), platform-account effective = 5; the live unit attaches **three** → effective **7**. Misleads an auditor into thinking the platform account isn't subject to `restrict-iam-users`/`require-tagging`. — **Evidence:** lines 44-46, 116-118, 138-145, 544 vs `organizations/terragrunt.hcl` `scp_attachments.Platform`. — **Fix:** update OU tree, inheritance diagram, effective table (4 root + 3 Platform = 7), budget table.
- [SEVERITY: high] `*-karpenter-*` exempt-role pattern wrong/security-misleading: doc lists a leading-wildcard; the live unit deliberately uses two pinned prefixes to avoid the broader grant. — **Evidence:** lines 468-469 vs `organizations/terragrunt.hcl:26-31`. — **Fix:** replace with the two explicit prefixes + anti-wildcard rationale.
- [SEVERITY: medium] Exempt-role count "six" is off — live `exempt_roles` has **seven**. — **Fix:** "seven entries"; split the karpenter row.
- [SEVERITY: low] for_each keys lowercase in walkthrough but PascalCase in code (`"Platform"`,`"Test"`,…). — **Fix:** capitalize.
- [SEVERITY: low] Verified-correct: OU tree shape, root/Workloads SCP sets, 7 default SCPs + HIPAA optional, lifecycle, `ArnNotLike` mechanism, SCP catalog SIDs.

## docs/architecture/crossplane-composition-authoring.md

- [SEVERITY: high] Claims the live template reads observed composed-resource status to gate domains ("the live template uses it"; tier-3 `Certificate Ready` gating). It does not — the only `.observed` access reads the XR's own spec; no `.observed.resources`/`Certificate`/`Pending` logic exists; status marks every `spec.domains` entry `Active`. — **Evidence:** lines 92-98, 114-118 vs `composition.yaml` (.observed only at L43-44; status L854-890). — **Fix:** reframe observed-status-read + tier-3 Pending as spike/Phase-2b design, not live.
- [SEVERITY: medium] EnvironmentConfig field list wrong: lists `podIdentityServiceAccnt` (not emitted), omits `resourcePrefix` (emitted + consumed). — **Evidence:** lines 62-64 vs `templates/environmentconfig.yaml:12-21`, composition L460/618/668/717. — **Fix:** swap `podIdentityServiceAccnt` → `resourcePrefix`.
- [SEVERITY: medium] Generated policy name given as `restrict-route-hostnames-<product>`; template renders `-<ns>` (`<team>-<product>-<stage>`). — **Evidence:** line 114 vs composition L908. — **Fix:** `-<ns>`.
- [SEVERITY: low] Calls it the `environment-v3` Composition; actual `metadata.name` is `environment`. — **Fix:** refer to the `environment` Composition.

## docs/architecture/crossplane-environment-api.md

- [SEVERITY: high] States the Composition provisions a `DeveloperAccess-<team>` IAM role + EKS access entry; it emits **only** the in-cluster `environment-developers` RoleBinding (#647 gap). The verification block (`aws eks describe-access-entry … DeveloperAccess-<team>`) would fail. — **Evidence:** lines 93-94, 158, 184-185 vs composition (`grep DeveloperAccess|AccessEntry` → none). — **Fix:** remove from "provisions" list/verification or mark deferred (#647).
- [SEVERITY: high] `status.domains` described as a working Pending→Active gate. Live template marks all domains `Active` and unconditionally allow-lists them. — **Evidence:** lines 60-72 vs composition L863-890. — **Fix:** Phase 2a = all bound domains rendered `Active`; mark Pending/external gating Phase 2b.
- [SEVERITY: low] `status.domains[]` documents `dnsTarget?`/`lastTransitionTime?`; template emits only host/state/mode/reason/message. — **Fix:** drop or mark reserved.
- [SEVERITY: low] Claim-sync app named `environments-preprod`; actual app is `environments`. — **Evidence:** `argocd-apps/delivery.tf:228`. — **Fix:** use `environments`.

## docs/architecture/platform-domain-api.md

- [SEVERITY: medium] Says F1's projected-CRD set is "four"; there are now **five** (a `Release` CRD added, ADR-071). — **Evidence:** line 52 vs `templates/release-crd.yaml`, `gitops/releases/**`. — **Fix:** five; add `Release`.
- [SEVERITY: medium] Inconsistent `Release`/ADR-071 status: spec table says `services.<svc>.image` retires "once ADR-071 is Accepted" and Open-Q #6 calls the promotion-artifact home unspecified; ADR-071 is now Accepted + live, yet the XRD still carries `services.<svc>.image` (they coexist). — **Evidence:** lines 233, 438-439, 522 vs `docs/adrs/071-...md:5`, `xenvironment-xrd.yaml:140`, `gitops/releases/alpha/shop/dev.yaml`. — **Fix:** mark ADR-071 implemented; resolve Open-Q #6; state image+Release coexist.
- [SEVERITY: low] Otherwise the XRD schema matches; "normative and LIVE" banner accurate.

## docs/architecture/tenant-api-v2.md

- [SEVERITY: low] Correctly marked superseded/historical (top banner).
- [SEVERITY: medium] Stale cross-refs: calls crossplane-environment-api.md "the current, interim contract" for v1alpha1 `XTenant` — that doc now documents the live v1beta1 `XEnvironment`; both pointers inverted. — **Evidence:** lines 20-21, 372. — **Fix:** update pointers; mark this a historical record.
- [SEVERITY: medium] Mislabels successor platform-domain-api.md as "the v1alpha3 schema"; it's **v1beta1**. — **Evidence:** line 8 vs xenvironment-xrd.yaml L30. — **Fix:** "v1beta1 / ADR-067."
- [SEVERITY: medium] Stale present-tense status (18-19, 388): "design-stage … land with the planned rebuild" / interim model "stands until the rebuild" — rebuild happened, v3 landed, those units deleted. — **Fix:** convert to past tense.

## docs/architecture/preprod-environment-model.md

- [SEVERITY: high] Claims the Composition provisions `DeveloperAccess-<team>` IAM role + EKS access entries; only the in-cluster RoleBinding exists (#647), and the security-boundary section leans on it. — **Evidence:** lines 293-294, 324-331, 416-418 vs composition.yaml. — **Fix:** describe only the RoleBinding; mark IAM role/access entry deferred (#647).
- [SEVERITY: medium] Presents alpha/demo + bravo/demo as live Environments; registries contain **alpha/{shop,checkout,conformance}** only — no demo product, no bravo. — **Evidence:** lines 34-35,39,57-99,307 vs `gitops/environments/alpha/*`, `gitops/products/alpha/*`. — **Fix:** use real names or relabel illustrative.
- [SEVERITY: medium] Points onboarding at nonexistent `infra/modules/crossplane/examples/environment-gamma.yaml` (only `smoke-ecr-repository.yaml` exists). — **Evidence:** line 356. — **Fix:** point to a real claim.
- [SEVERITY: low] Supply-chain policy names `verify-images-<product>`; actual `verify-images-product-<team>-<product>`. — **Fix:** full form.
- [SEVERITY: low] Verified-correct: provisioned-resource table, NetworkPolicy/CNP set, PSA labels, quota defaults, Pod-Identity model (ADR-041).

## docs/architecture/cosign-image-signing.md

- [SEVERITY: high] §7/§10 claim Kyverno reads ECR signatures via **IRSA** (OIDC `sub`; deny-triage step checks SA `eks.amazonaws.com/role-arn`). Mechanism is now **EKS Pod Identity** (ADR-047/#594) — the troubleshooting step looks for an annotation that no longer exists. — **Evidence:** `policy/main.tf:189` (`pods.eks.amazonaws.com`), :236-242; doc lines 327-345, 436. — **Fix:** rewrite §7 + §10 step-3 for Pod Identity.
- [SEVERITY: medium] §5/§6/§8 imply `appSubjects` populated for every product + a live `legacy_org` scaffold; live units populate **no** appSubjects (fallback inert) and `legacy_org`/`gangster` exist nowhere in `infra/live`. — **Evidence:** `preprod/.../policy/terragrunt.hcl:30-34`; `grep legacy_org infra/live` → none. — **Fix:** mark fallback available-but-unused; show the real 4-field map.
- [SEVERITY: low] §6 HCL drifts from live shape. — **Fix:** sync illustrative HCL.

## docs/architecture/supply-chain-overview.md

- [SEVERITY: low] Largely accurate (per-product `githubWorkflowRepository` gating, predicate types, `needs:[build-sign,provenance]` barrier, SLSA L3 matrix verified). Soft note: app-signed fallback is presented as supported but is currently unpopulated in both live units — worth a one-line "not currently used."

## docs/architecture/kyverno-policy-catalog.md

- [SEVERITY: high] Omits the entire ADR-085 availability suite (self-described "authoritative list"): no `require-prod-replica-floor`, `mutate-topology-spread`, or `generate-workload-pdb` (ADR-085 appears 0× in the file). `require-prod-replica-floor` is now **Enforce** on both clusters. — **Evidence:** templates `require-replica-floor.yaml`, `mutate-topology-spread.yaml`, `generate-pdb.yaml`; `replica_floor_failure_action="Enforce"` both units. — **Fix:** add all three; cite ADR-085.
- [SEVERITY: high] Claims the platform cluster "carries just the common policies" and "has no environment workloads." False — the platform unit enables image+attestation verification and derives `verify_subjects_product` from the same unfiltered `fileset(gitops/products)`, so `verify-*-product-*` render on platform too (triage-copilot, ADR-082). — **Evidence:** `platform/.../policy/terragrunt.hcl:116-119`; doc lines 28, 114. — **Fix:** correct the platform-cluster description.
- [SEVERITY: medium] Stale product count rationale ("alpha-shop + alpha-checkout, two policies each"); there are **4** products. — **Fix:** four (or drop hard numbers).
- [SEVERITY: medium] Scope legend contradictory + names a nonexistent label: defines "tenant" but rows say "environment"; cites `platform.refplat.org/environment` (exists nowhere) — real label is `platform.refplat.org/team`. — **Evidence:** `policies-chart/values.yaml:37`. — **Fix:** rename legend term + label.
- [SEVERITY: medium] `restrict-images`/`restrict-route-hostnames` rows say "preprod (alpha-shop, alpha-checkout)"; live envs are shop/dev, **shop/prod**, checkout/dev, conformance/dev. — **Fix:** reflect all 4 (prod stage matters now replica-floor is Enforce).

## docs/architecture/kyverno-shift-left.md

- Accurate and complete. Verified `gitops-gate.yml`, all named validate/render scripts, removed `kyverno-validate` action, `kyverno-policy-test` job + `.kyverno-tests/` dirs, the envelope admission-rule names, the 1.18.1/3.8.1 CLI pin.

## docs/architecture/delivery-pipeline.md

- [SEVERITY: medium] `gitops/grants/` registry-sync described as "planned — P4, not yet built" (×2), but the projection is built/live (`argocd-apps/delivery.tf:231` `grants` app at wave 0; `gitops/grants/README.md`). Only consumption + authored grants are pending. — **Evidence:** lines 84, 166. — **Fix:** split: projection live, consumption pending.
- [SEVERITY: low] "Environment claims ship `preview: false`" — no `preview` field exists. — **Fix:** drop the detail.
- Otherwise accurate (module/workflow paths, registry→CR table, ADR cites verified).

## docs/architecture/promotion-and-release.md

- [SEVERITY: high] "Not yet built" section calls prod progressive delivery "Proposed" and says "Today a prod promotion is a plain 100%-at-once ArgoCD sync." Stale — `argo-rollouts` is a live control plane (ADR-056); the scaffolder's prod overlay ships a canary/blue-green Rollout with metric gate; zero-downtime-deployments.md states Rollouts-everywhere live on alpha-shop prod. — **Evidence:** lines 188-193 vs `argo-rollouts/README.md:4`, `scaffolder/.../overlays/prod/progressive.yaml`. — **Fix:** rewrite — prod is Rollout-based; cross-link zero-downtime-deployments.md.
- Otherwise accurate: 5-stage ladder dev→test→uat→staging→prod, release-keyed ApplicationSet, gated-prod machinery, all script paths verified.

## docs/architecture/zero-downtime-deployments.md

- [SEVERITY: low] ArgoCD-integration narrative cites `ignoreDifferences`+`RespectIgnoreDifferences` but omits the `ServerSideApply=true` + `managedFieldsManagers=["rollouts-controller"]` companion (the #894-critical part). — **Evidence:** lines 64-66, 95 vs `delivery.tf:162,182`. — **Fix:** add SSA + managed-fields ignore.
- Otherwise accurate/current: ADR-085 defaults live, replica-floor Enforce, Rollouts-everywhere, Gateway-API weighted router, Beyla→Mimir metric flow.

## docs/architecture/gateway-and-ingress.md

- [SEVERITY: medium] cert-manager + external-dns described as authenticating to Route53 via **IRSA**; both now use **EKS Pod Identity (ADR-047)** with no IRSA annotation. — **Evidence:** lines 60-62, 73 vs `cert-manager/main.tf:21-22,105-113`, `external-dns/main.tf:26-27,88-96`. — **Fix:** replace "IRSA" with "EKS Pod Identity (ADR-047)".
- [SEVERITY: low] "argocd-apps injects … the `-pr-*` preview wildcard" — actual injection is a `preview_domain`-gated host. — **Evidence:** `delivery.tf:129-134`. — **Fix:** describe the preview-domain host patch.
- [SEVERITY: low] Never mentions the `gateway`/`gateway-config` split. — **Fix:** optional one-line note.
- Otherwise accurate: shared Gateway, two listeners, internal NLB, ClusterIssuer, `ingress` identity (8), cilium-secrets copy, custom-domain deferral verified.

## docs/architecture/config-hierarchy.md

- [SEVERITY: medium] Stale AWS provider pin: says `versions.tf` pins AWS to **6.47.0**; `root.hcl:40` now generates `~> 6.0` as a fallback-only block (module `versions.tf` authoritative, ADR-083). — **Evidence:** line 119 vs `root.hcl:31-40`. — **Fix:** `~> 6.0`, note fallback-only.
- [SEVERITY: low] Module-source count "~61"; actual `module_source` entries in `_versions.hcl` = **66**. — **Fix:** "~66".
- Otherwise accurate: `_base.hcl` assertions, six-config read, `all_vars` merge, provider generation, SOPS flow, ADR cross-links.

## docs/architecture/secrets-and-external-secrets.md

- [SEVERITY: high] Central "Authentication is IRSA" claim stale throughout. ESO migrated to **EKS Pod Identity** (ADR-047/#594): `external-secrets/main.tf:60,121`; `secret-stores/main.tf:23-24,49-50`. Invalidates the lede, end-to-end chain, "ESO controller (IRSA)" heading, trust-policy/OIDC text, `auth.jwt`/`serviceAccountRef` description, the status-table IRSA rows. — **Evidence:** lines 6-7, 35, 38, 42-43, 60-62, 102-103, 117. — **Fix:** rewrite as Pod Identity (no OIDC federation, no `auth.jwt`, no annotation).
- [SEVERITY: medium] Broken verification step (line 139): `kubectl describe sa external-secrets … eks.amazonaws.com/role-arn present` — annotation doesn't exist under Pod Identity; check always fails. — **Fix:** verify via `aws eks list-pod-identity-associations`.
- [SEVERITY: medium] Line 102 lists Dex as a live secret-consuming service; Dex is dormant. — **Fix:** drop Dex.

## docs/architecture/observability-current-state.md

- [SEVERITY: high] Internal contradiction on Mimir enablement: line 28 correctly says Mimir ON on the platform hub, but lines 95-97, 237, 297-300 assert it's off ("Prometheus-only in dev … no remote_write"). Ground truth: `platform/env.hcl:13` `enable_mimir=true`. — **Fix:** delete the "Mimir off in dev" passages.
- [SEVERITY: high] Internal contradiction on Grafana SSO: body (36-40) correctly says Keycloak OIDC live (#592); Status notes (304-305) say "deferred hardening — admin login for now." Module confirms live (`observability/main.tf:53-76`). — **Fix:** delete the stale note.
- [SEVERITY: medium] Mimir S3 auth mislabeled IRSA (93, 249-251); already Pod Identity. — **Fix:** move Mimir to Pod-Identity column.
- [SEVERITY: medium] Alertmanager→SNS auth mislabeled IRSA (72, 224); now Pod Identity (`observability/main.tf:294,571`; CloudWatch datasource likewise). — **Fix:** "sigv4 via Pod Identity." (Stale "IRSA" comments also linger in `sns-notifications/main.tf:4` and `observability/variables.tf:55`.)
- Cross-links + 17 observability* modules verified.

## docs/architecture/platform-capability-coverage.md

- [SEVERITY: low] "Last reviewed: 2026-06-23" trails content (already reflects later-shipped Grafana SSO, OpenCost, Falco). Status claims spot-check accurate (Karpenter/spot-retired, OpenCost live, Falco preprod, federated multi-cluster, enterprise rows correctly designed-not-built); all 19 ADR + 2 doc cross-links resolve. — **Fix:** bump review date; no substantive corrections.

---

## Cross-cutting note

1. **IRSA→Pod Identity (ADR-047/#594) is the dominant stale theme** — HIGH/MEDIUM in five docs: cosign-image-signing (Kyverno ECR + a broken triage step), secrets-and-external-secrets (worst hit), gateway-and-ingress (cert-manager/external-dns), observability-current-state (Mimir/SNS/CloudWatch). Several modules also carry stale "IRSA" *comments*. A single "IRSA" sweep across `docs/architecture/` clears most items.
2. **The #647 `DeveloperAccess-<team>` gap is documented as built in three docs** (crossplane-environment-api, preprod-environment-model, identity-and-sso implied) — each presents an IAM role + EKS access entry the Composition does not emit. Highest operational-risk cluster: verification commands fail, engineer assumes access that doesn't exist.
3. **Crossplane `status.domains` Pending→Active gate over-claimed as live** in two docs — the live template marks everything `Active`; the real boundary is Kyverno admission. Needs a global "Phase 2a vs 2b" disclaimer.
4. **Argo Rollouts / ADR-085 lag in the catalog-style docs**: kyverno-policy-catalog omits the entire ADR-085 suite + mislabels replica-floor; promotion-and-release still calls prod progressive delivery "Proposed."
5. **Registry-as-source-of-truth out-ran several docs**: people/roles/grants registries + generators are built (#886-889) but identity-and-access-strategy, identity-and-sso, delivery-pipeline still describe them as planned/hand-maintained.
6. **tenant-api-v2.md** correctly banner-marked historical, but its internal body + cross-refs read present-tense and point at now-inverted "current/target" relationships.
7. **No broken cross-links** in any of the 21 docs — issues are factual currency, not dead links. Drifted counts: exempt-roles (6→7), module sources (~61→66), projected CRDs (4→5), products (2→4).
