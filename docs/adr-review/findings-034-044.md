# ADR Accuracy Review — ADRs 034–044

Reviewer: adversarial accuracy pass. Checkout: `/Users/josh/centric/platform-adr-review` (worktree at origin/main). All paths/line numbers cited are from this checkout.

---

## ADR-034: Transit Gateway for Cross-Account VPC Connectivity

- **Status quoted:** `**Status:** Accepted`
- **Findings:**
  - [SEVERITY: low] Core claims verified correct. `create_tgw` / `ram_share_principals` / `setproduct` exist in the module. — **Evidence:** `infra/modules/aws/transit-gateway/variables.tf:12,30`, `main.tf:3,8,56` — **Proposed fix:** none.
  - [SEVERITY: low] Transit-subnet tier `transit = { newbits = 4, netnum = 15, public = false } # /28` present verbatim in every env's `network.hcl`. — **Evidence:** `infra/live/aws/platform/us-east-1/network.hcl:16`, `preprod/...:16`, `prod/...:11` — **Proposed fix:** none.
  - [SEVERITY: low] Spoke dependency `config_path = "../../../../platform/us-east-1/platform/transit-gateway"`, spoke-mode `create_tgw = false`, port-443 SG rule all real. — **Evidence:** `infra/live/aws/preprod/us-east-1/platform/transit-gateway/terragrunt.hcl:36,48,67` — **Proposed fix:** none.
- **Decision concerns:** none. Cost/scaling tradeoff vs peering is sound and the module matches the prose.

## ADR-035: Cross-VPC DNS Resolution for Private EKS Endpoints

- **Status quoted:** `**Status:** Accepted`
- **Findings:**
  - [SEVERITY: low] Verified accurate. `dns_method` validation accepts exactly `phz`/`resolver_outbound`/`resolver_inbound`; `phz_records` + `eks_lookup_role_arn`; TTL default 60. — **Evidence:** `infra/modules/aws/cross-vpc-dns/variables.tf:12-19,32-39` — **Proposed fix:** none.
  - [SEVERITY: low] Live unit confirms `dns_method = "phz"`, `https://`-stripping for the domain, and the cross-account `PlatformDeployer` role in preprod for ENI lookup. — **Evidence:** `infra/live/aws/platform/us-east-1/platform/cross-vpc-dns/terragrunt.hcl:45,50-52` — **Proposed fix:** none.
- **Decision concerns:** none.

## ADR-036: GitHub Actions OIDC Federation for CI/CD

- **Status quoted:** `**Status:** Accepted`
- **Findings:**
  - [SEVERITY: medium] **Stale implementation, no amendment.** The "Per-Team ECR Push Roles" section claims roles `github-actions-ecr-push-<team>` from a `roles = { for team, cfg in local.teams ... }` map, scoped to `team-<team>/*`. The live unit is now **per-Product**, derived from the **Product registry** (`gitops/products/**`): role name `github-actions-ecr-push-product-<product>`, ECR scope `team-<team>/<product>-*`, branches `["main","refs/tags/*"]` (not just `["main"]`), broader inline policy (adds `ecr:DescribeRepositories`, `GetDownloadUrlForLayer`, `BatchGetImage`, plus `secretsmanager:GetSecretValue` on `platform/promote/github-app-*`). This is the registries-as-single-source migration (ADR-061/063/067/069); CLAUDE.md confirms `github-oidc` now derives per-Product and `teams.hcl` is retired. — **Evidence:** `infra/live/aws/platform/us-east-1/platform/github-oidc/terragrunt.hcl:30-75` — **Proposed fix:** add an amendment (like ADRs 039/041) and update the snippet, or mark it "historical."
  - [SEVERITY: medium] **Both code snippets reference a module interface that no longer exists.** ADR shows the Test role as flat top-level inputs `github_repo`, `github_branches`, `role_name`, `role_policy_arns`, `max_session_duration`. The `github_oidc` module exposes only `create`, `github_org`, `roles`, `tags`; per-role attributes live inside the `roles` map. — **Evidence:** `infra/modules/aws/github_oidc/variables.tf` (4 vars only); `infra/live/aws/test/global/github-oidc/terragrunt.hcl:18-50` — **Proposed fix:** rewrite both snippets to the actual `roles`-map interface.
  - [SEVERITY: medium] The Terratest `AdministratorAccess` "Negative" bullet credits only "no production data + branch protection." The live unit now adds an explicit **Deny overlay** (`DenyPersistenceEscalationAndGuardrailDisable`) blocking IAM-user/key/federation creation, `organizations:*`, `account:*`, and audit/detection teardown — a materially stronger mitigation the ADR under-states. — **Evidence:** `infra/live/aws/test/global/github-oidc/terragrunt.hcl:32-48` — **Proposed fix:** mention the Deny overlay.
  - [SEVERITY: low] Verified-correct: thumbprint sentinel `ffff…ffff` and the `create` variable for sharing a provider. — **Evidence:** `infra/modules/aws/github_oidc/main.tf:44-45`, `variables.tf:1` — **Proposed fix:** none.
- **Decision concerns:** The decision (OIDC over keys) is sound and unchanged; only the implementation narrative drifted. Worth an amendment so readers don't author against the dead flat-variable interface.

## ADR-037: CloudTrail for Secrets Audit Logging

- **Status quoted:** `**Status:** Accepted`
- **Findings:**
  - [SEVERITY: low] Verified accurate: module resources, defaults (`log_retention_days` 90, `cloudwatch_retention_days` 30, `force_destroy` false, `is_multi_region` false, `enable_cloudwatch` true), alarm name `<trail-name>-secrets-write-activity`, `treat_missing_data = "notBreaching"`, and metric-filter pattern matching `GetSecretValue||PutSecretValue||CreateSecret||DeleteSecret`. — **Evidence:** `infra/modules/aws/cloudtrail/variables.tf:12-75`, `main.tf:214-244` — **Proposed fix:** none.
  - [SEVERITY: low] "No SNS topic configured" is still true (no `alarm_actions`). — **Evidence:** `grep alarm_actions|sns infra/modules/aws/cloudtrail/*.tf` → no matches — **Proposed fix:** none.
  - [SEVERITY: low] Minor imprecision: the alarm is named `...-secrets-write-activity` and ADR §4 says it fires "when any secrets write operation occurs," but the filter also counts `GetSecretValue` (a read) with `threshold = 0`, so it fires on **any** secrets activity. The module's `alarm_description` shares the mislabel. — **Evidence:** `infra/modules/aws/cloudtrail/main.tf:218,232-241` — **Proposed fix:** reword to "any Secrets Manager activity (reads + writes)."
- **Decision concerns:** none. Unusually careful ADR (correctly pre-empts the GetSecretValue-management-event misconception).

## ADR-038: platctl CLI for Platform Operations

- **Status quoted:** `**Status:** Accepted`
- **Findings:**
  - [SEVERITY: medium] **Stale command surface.** ADR says "**five subcommands**" (bootstrap, teardown, validate, kubeconfig, status). The binary has **seven** — it also ships `down`/`up` (cluster park/unpark, ADR-078), in `scale.go`; CLAUDE.md and the `platctl` skill treat park/unpark as first-class. — **Evidence:** `cmd/platctl/internal/cli/scale.go:26` (`Use: "down --env <env>"`), `:82` (`Use: "up --env <env>"`) — **Proposed fix:** add `down`/`up` to the list (or an amendment).
  - [SEVERITY: low] "Four internal packages" omits the `cli` package now present. — **Evidence:** `cmd/platctl/internal/cli/` — **Proposed fix:** add `cli` or soften the count.
  - [SEVERITY: low] Verified-correct: `cmd/platctl/` layout, config/engine/cloud/validate packages, the three hooks, `.platctl.yaml`, AWS-CLI-not-SDK cloud package. — **Evidence:** `cmd/platctl/internal/{config,engine,cloud,validate}/*.go` — **Proposed fix:** none.
- **Decision concerns:** none on the decision; keep the command inventory current (CLI surface drifts fastest).

## ADR-039: Per-Team Developer RBAC

- **Status quoted:** `**Status:** Accepted`
- **Findings:**
  - [SEVERITY: high] **The amendment overstates what is actually provisioned.** It says the `DeveloperAccess-<team>` IAM role, the EKS access entry, **and** the namespace RoleBinding "are now rendered per team by the Crossplane … Composition." In reality the v3 Composition emits **only the developer RoleBinding** — the IAM role + access entry are **not yet emitted** (regression #647). CLAUDE.md flags this ("⚠️ NOT currently provisioned … use `platctl kubeconfig`/PlatformAdmin until built"). A reader would wrongly conclude per-team developer cluster access works end-to-end. — **Evidence:** `infra/modules/crossplane/README.md:15-19` ("…**not yet emitted** by the v3 Composition — a regression tracked in [#647]"); composition renders only `rolebinding-developers` at `charts/environment-api/files/composition.yaml:274-291` — **Proposed fix:** correct the amendment to "only the RoleBinding is emitted; IAM role + access entry are a known gap (#647)."
  - [SEVERITY: high] **Wrong group name and ClusterRole.** Amendment/body say group `team-<team>:developers` bound to ClusterRole `tenant-developer`. The shipped Composition binds group `<environment-namespace>:developers` (e.g. `alpha-demo-dev:developers`) to ClusterRole `environment-developer` (CLAUDE.md agrees). — **Evidence:** `composition.yaml:283,288,291`; `charts/environment-api/templates/environment-developer.yaml:9`; `.environment-api-tests/render.sh:25` (`name: alpha-demo-dev:developers`) — **Proposed fix:** update group/ClusterRole names; they are per-Environment-namespace, not per-team.
  - [SEVERITY: medium] **Superseded terminology / source of truth.** Leans on "Crossplane **Tenant** Composition," the `tenant` module, and `teams.hcl` as single source of truth. v3 (ADR-067) renamed Tenant→Environment, **deleted** `infra/modules/tenant`, and retired `teams.hcl` for the git-native registries. — **Evidence:** `ls infra/modules/tenant` → absent; CLAUDE.md "the app-delivery `teams.hcl` is retired" — **Proposed fix:** re-amend to Environment/XEnvironment + registry terminology.
- **Decision concerns:** Model is sound, but the ADR reads as "shipped" when the IAM/access-entry half is a known regression. Highest-risk inaccuracy in the batch — reconcile against #647.

## ADR-040: Platform Engineer Access Model

- **Status quoted:** `**Status:** Accepted`
- **Findings:**
  - [SEVERITY: low] Mechanism verified: `platform-operator` ClusterRole, group `platform-operators`, `AmazonEKSViewPolicy` for read, exact added verbs (pods/log, pods/exec, pods/portforward, delete pods, pods/eviction, patch nodes, patch deployments/statefulsets/daemonsets). — **Evidence:** `infra/modules/cluster-rbac/main.tf:18,30,55,68,120`, `README.md:11-14`, `variables.tf:8-10` — **Proposed fix:** none.
  - [SEVERITY: medium] **Residual-risk note is stale.** The `pods/exec` consequence claims `disallow-irsa-annotation-cross-team` means "there is no workload IAM role for an exec'd shell to assume today (… until per-team IRSA lands)." Per-team workload AWS access has since landed as **Pod Identity** (ADR-041/047), not IRSA — so where a team declares `policyStatements`, an exec'd shell **can** reach the Pod Identity endpoint (`169.254.170.23`) and assume the team's role. The "no workload IAM role to assume" assurance no longer holds. — **Evidence:** ADR-041 decision + `composition.yaml:441-446` (per-service Pod-Identity role from `policyStatements`); CLAUDE.md "environment AWS access is … Pod Identity (ADR-041)" — **Proposed fix:** reframe the mitigation — per-team identity now exists via Pod Identity.
- **Decision concerns:** Decision sound; one consequence needs refreshing post-ADR-041.

## ADR-041: EKS Pod Identity for Tenant Workloads

- **Status quoted:** `**Status:** Accepted — narrows ADR-018 … Broadened by ADR-047 …`
- **Findings:**
  - [SEVERITY: low] Mechanism verified: `eks-pod-identity` module exists; `policyStatements`-driven per-service Pod-Identity IAM rendered by the Composition; the Cilium `host`-entity egress + IMDSv2 hop-limit reasoning matches platform stance. Runbook target `../runbooks/environment-aws-access-pod-identity.md` exists. — **Evidence:** `infra/modules/aws/eks-pod-identity/`; `composition.yaml:441-446`; `docs/runbooks/environment-aws-access-pod-identity.md` — **Proposed fix:** none.
  - [SEVERITY: medium] **"Components" section lists retired units.** It lists "new `pod-identity` (preprod), new `s3-shared` (platform account)" units. Both are **gone** — folded into the Crossplane Composition (CLAUDE.md: the old v2 `pod-identity`/`s3-shared` units are retired). The top amendment flags the S3 *demo* as illustrative but doesn't retire the unit references in Components. — **Evidence:** `find infra/live -path '*pod-identity*' -o -path '*s3-shared*'` → no matches — **Proposed fix:** mark the Components unit list historical; provisioner is the `crossplane` Composition.
  - [SEVERITY: low] Superseded naming: `XTenant` claim / `Pod-team-<team>` role presented as current; v3 uses `XEnvironment` with per-service `Pod-*` roles and `permissions.aws.policyStatements`. — **Evidence:** `xenvironment-xrd.yaml:163` (`policyStatements:` under service permissions) — **Proposed fix:** note the XTenant→XEnvironment rename.
- **Decision concerns:** Decision is correct and now the platform standard (ADR-047, #594 LIVE). Only unit/claim naming drifted.

## ADR-042: Isolated Build Provenance for SLSA Build L3

- **Status quoted:** `**Status:** Accepted — extends ADR-036 … P1–P3 done on preprod … P4 … pending. Generalized by ADR-050 …`
- **Findings:**
  - [SEVERITY: low] cosign pin `v2.5.2` consistent with the repo's cosign pin. The `trusted-ci` signer repo is external (`asanexample/trusted-ci`), not in this checkout, so the L3 cert-identity claims can't be machine-verified here. — **Evidence:** `.github/workflows/gha-runner-image.yml:68` (`cosign-release: "v2.5.2"`) — **Proposed fix:** none.
  - [SEVERITY: low] **NEEDS LIVE/OWNER VERIFICATION:** P3 "Build L3 achieved on preprod" / verify-attestations Enforce, and P4 "platform `policy` unit does not yet carry trusted-ci verification" are runtime/external-repo claims. They match project memory (SLSA L3 done; #138) but aren't verifiable from this repo. — **Proposed fix:** none (status reads honestly as phased).
- **Decision concerns:** none. The L3 reasoning (reusable-workflow Fulcio SAN; `job_workflow_ref` not honored by AWS STS) is precise and caveated.

## ADR-043: Self-Hosted Prometheus/Grafana Observability Stack

- **Status quoted:** `**Status:** Accepted — P1 implemented + live on the platform cluster …`
- **Findings:**
  - [SEVERITY: low] Chart pin verified: `kube-prometheus-stack` `helm_chart_version` default `86.1.0`. — **Evidence:** `infra/modules/observability/variables.tf:72-75` — **Proposed fix:** none.
  - [SEVERITY: low] "Live on platform cluster" matches project memory (observability P1–P7+P11 live); no contradiction found in-repo. — **Proposed fix:** none.
- **Decision concerns:** none.

## ADR-044: Grafana Mimir for Durable, Multi-Tenant Metrics Storage

- **Status quoted:** `**Status:** Accepted — P2 implemented + live on the platform cluster …`
- **Findings:**
  - [SEVERITY: low] Chart pin verified: `mimir-distributed` default `6.0.6` (and the "6.0.x stable / 6.1.0-weekly dev-only" note matches the variable description). — **Evidence:** `infra/modules/observability-mimir/variables.tf:69-75` — **Proposed fix:** none.
  - [SEVERITY: low] `X-Scope-OrgID`-trust-header + NetworkPolicy-isolation + SSE-S3-to-avoid-KMS rationale is internally consistent with the module. — **Proposed fix:** none.
- **Decision concerns:** none.

---

## Cross-cutting note

The dominant theme is **post-v3 / registries-as-single-source drift in the access-and-identity ADRs (036, 039, 040, 041)**. All four predate the Tenant→Environment rename (ADR-067) and the migration of per-team derivation from `teams.hcl` to the git-native Product/Environment registries. They variously still say `teams.hcl`, `tenant`/`XTenant`, `Pod-team-<team>`, `team-<team>:developers`, and list now-deleted units (`pod-identity`, `s3-shared`, the `tenant` module). ADRs 039 and 041 carry amendments, but the amendments are themselves pre-v3 and — in ADR-039's case — **over-claim provisioning that is actually a known regression (#647)**, the single highest-risk item in the batch. By contrast the infrastructure ADRs (034, 035, 037, 038, 042, 043, 044) are accurate down to the version pins, with 038's missing `down`/`up` subcommands the only notable staleness.
