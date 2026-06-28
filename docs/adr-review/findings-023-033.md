# ADR Accuracy Review — ADRs 023–033

Adversarial accuracy pass against `/Users/josh/centric/platform-adr-review` (latest origin/main). All evidence is from this checkout.

---

## ADR-023: EKS Managed Node Groups over Self-Managed or Karpenter
- **Status quoted:** `Accepted — **partly superseded by [ADR-078](078-cluster-elasticity-karpenter.md)**: Karpenter now provisions and consolidates *workload* nodes; managed node groups are retained only for the fixed `system` (controller/bootstrap) floor.`
- **Findings:**
  - [SEVERITY: medium] The **Node Group Configuration table** is stale on every value. It lists `system` t3.large 2–4 and `workload` t3.large 1–6, "Both groups span all 3 AZs." Reality: only the `system` group exists (workload group **retired**, Karpenter owns it), instance is **t4g.xlarge / t3.xlarge (4 vCPU/16 GiB)** not t3.large, system is **min 2 / max 3**, and groups are **single-AZ** in the dev profile. The status note flags the workload→Karpenter supersession but the body table still shows concrete wrong numbers. — **Evidence:** `infra/live/aws/platform/us-east-1/platform/node-groups/terragrunt.hcl:48,60-80,69-71,58` — **Proposed fix:** add a current-sizing note: single `system` group, t4g.xlarge/t3.xlarge, 2–3, single-AZ; workload = Karpenter (ADR-078).
  - [SEVERITY: low] "pods use IRSA, ADR-018" is stale — pod AWS identity is now **Pod Identity** (ADR-047; ADR-018 marked superseded in the index). IMDSv2 rationale itself still valid. — **Evidence:** `docs/adrs/README.md:89`; `infra/modules/external-secrets/main.tf:121`.
  - [SEVERITY: low] Closing risk "The platform currently has no cluster autoscaling (Cluster Autoscaler or Karpenter)…" contradicts the ADR's own status line. — **Proposed fix:** strike/mark historical.
  - [SEVERITY: low] Verified correct: four managed policies, IMDSv2 `http_tokens=required`+`hop_limit=1`, gp3 `encrypted=true`, `node-role` label. — **Evidence:** `infra/modules/aws/eks-node-group/main.tf:30,37,44,52,74,76,82,83`.
- **Decision concerns:** Decision is sound but only partly updated for ADR-078; config table left as v1. Move it to a "historical (pre-Karpenter)" block or fold in current sizing.

---

## ADR-024: Secrets Management Architecture
- **Status quoted:** `Accepted`
- **Findings:**
  - [SEVERITY: medium] The **Identity Model** rests on IRSA ("ESO to Secrets Manager: IRSA (ADR-018)"). ESO now authenticates via **EKS Pod Identity** — module creates `aws_eks_pod_identity_association`; ClusterSecretStores drop `serviceAccountRef` to use the controller identity (ADR-047/#594). — **Evidence:** `infra/modules/external-secrets/main.tf:17-18,121`; `infra/modules/secret-stores/main.tf:6,32` — **Proposed fix:** amend to Pod Identity (ADR-047); path-scoping unchanged.
  - [SEVERITY: low] Implementation Status table **verified accurate**: path-scoped IAM `secret:${prefix}/*` (`main.tf:85`, var `secret_path_prefix` `variables.tf:39`); `secret-stores` ClusterSecretStore (SM + SSM) on platform **and** preprod (both units exist); legacy `charts/secrets/` **removed** (absent).
  - [SEVERITY: low] "PlatformAdmin is denied `secretsmanager:GetSecretValue` (ADR-040)" — **verified correct**. — **Evidence:** `infra/live/aws/platform/us-east-1/platform/iam-roles/terragrunt.hcl:55-58` (`DenySensitiveDataReads`).
  - [SEVERITY: low] Context "five AWS accounts across **three OUs**: Management, Platform, Workloads" — management is at the **org root**, not an OU (cf. ADR-026:9-12). Minor imprecision.
  - [SEVERITY: low] **NEEDS LIVE/OWNER VERIFICATION:** Prod-specific controls (30-day window, KMS CMK, CloudTrail data events) — Prod not online; design intent.
- **Decision concerns:** IRSA→Pod-Identity drift is shared across 024/025/026/029/030 (cross-cutting). Decision unaffected.

---

## ADR-025: Secret Naming Convention and Path Hierarchy
- **Status quoted:** `Accepted`
- **Findings:**
  - [SEVERITY: low] "IRSA policies (ADR-018)" in IAM Integration — scoping is now on a **Pod Identity** role (ADR-047). Path/ARN patterns unchanged and accurate. — **Evidence:** `external-secrets/main.tf:85,121`.
  - [SEVERITY: low] Convention itself consistent with ADR-024 and the module's `secret_path_prefix`. No factual issue; "adopted, not yet policy-enforced" remains honest.
- **Decision concerns:** none beyond IRSA wording.

---

## ADR-026: Cross-Account Secret Isolation
- **Status quoted:** `Accepted`
- **Findings:**
  - [SEVERITY: low] Architecture diagram annotates ESO as "ClusterSecretStore (IRSA → this account only)"; auth is now **Pod Identity** (ADR-047), and per-cluster trust is the Pod Identity association rather than the OIDC-issuer trust policy the Context describes. Isolation property unchanged. — **Evidence:** `external-secrets/main.tf:17-18,121`; `secret-stores/main.tf:6`.
  - [SEVERITY: low] 5-account/OU framing **verified consistent**; preprod ClusterSecretStore deployed; Prod ESO pending (not online).
  - [SEVERITY: low] **NEEDS LIVE/OWNER VERIFICATION:** the single registry cross-account exception (`platform/registry/*` + `aws:PrincipalOrgID`) — not present in-repo; design intent.
- **Decision concerns:** none beyond shared IRSA wording. Strong ADR.

---

## ADR-027: Hybrid Tenant Isolation Model
- **Status quoted:** `Accepted (vCluster mode deferred — see ADR-033)`
- **Findings:**
  - [SEVERITY: low] Both amendment banners correctly flag `infra/modules/tenant` + `tenants` unit retired — **verified** (module absent, no `teams.hcl`). Body marked historical. Good hygiene.
  - [SEVERITY: low] First amendment names the replacement "Crossplane `Tenant` Composition (kind `XTenant`)." That v2 surface was **removed** at v3 cutover; sole composite is now **`XEnvironment`** (ADR-067). — **Evidence:** `infra/modules/crossplane/.environment-api-tests/README.md:6`; `charts/environment-api/templates/xenvironment-xrd.yaml:24` — **Proposed fix:** append "(later renamed `XEnvironment`, ADR-067)".
- **Decision concerns:** Heavily layered; isolation primitives still live, provisioning mechanism + kind name drifted.

---

## ADR-028: ECR Cross-Account Container Registry
- **Status quoted:** `Accepted`
- **Findings:**
  - [SEVERITY: medium] **Repository Structure** stale. Shows `team-alpha/demo`/`team-bravo/demo` created by this unit, "keys match `teams.hcl` apps." Today tenant ECR repos are **Crossplane Composition-owned** (`provider-aws-ecr`); the `ecr` unit holds only **platform repos** (`platform/backstage`, `platform/gha-runner`); `teams.hcl` gone. — **Evidence:** `infra/live/aws/platform/us-east-1/platform/ecr/terragrunt.hcl:21-38` — **Proposed fix:** add status note that per-team repos moved to the Composition.
  - [SEVERITY: medium] Risk note cites Kyverno **`verify-images-team-<team>`**. Current naming is **per-product**: `verify-images-product-<team>-<product>` / `verify-attestations-product-<team>-<product>` (ADR-046 split/ADR-067). — **Evidence:** `infra/modules/policy/README.md:30`; `.kyverno-tests/run.sh:98-99` — **Proposed fix:** update name + note the producer split.
  - [SEVERITY: low] "`image_tag_mutability = IMMUTABLE_WITH_EXCLUSION`" — module variable is `tag_mutability` (the AWS attribute is `image_tag_mutability`). Cosmetic. — **Evidence:** `ecr/variables.tf:10`.
  - [SEVERITY: low] Verified correct: exclusion default `["sha256-*"]` (`variables.tf:24`), `max_image_count` 50 (`:41`), untagged-7d (`main.tf:83-88`), keep-last-N (`:100-101`), `scan_on_push=true` (`main.tf:31`), `AES256` (`main.tf:35`), node `AmazonEC2ContainerRegistryReadOnly`, pull to preprod+prod, live unit path exists.
- **Decision concerns:** Centralized-ECR decision intact; ADR not re-touched after tenant repos moved to Crossplane and policy naming went per-product.

---

## ADR-029: Preprod Public Ingress via Gateway API
- **Status quoted:** `Accepted`
- **Findings:**
  - [SEVERITY: medium] Attributes the NLB-scheme control to the **`gateway-config`** module ("supports an `internal` boolean variable that controls the NLB scheme"). The Gateway (with `internal`/scheme, Let's Encrypt cert, Route53) **split into a separate `gateway` module/unit**; `gateway-config` no longer has `internal`/`letsencrypt_email`/`route53_*`. — **Evidence:** `infra/modules/gateway-config/variables.tf` (only create/domain/gateway_name/gateway_namespace/routes); `infra/modules/gateway/variables.tf:54`, `main.tf:66-68`; `…/preprod/.../gateway-config/terragrunt.hcl:88-90` — **Proposed fix:** retarget prose to the `gateway` module; note the split.
  - [SEVERITY: medium] The **Implementation `inputs` block** is stale: `internal`, `letsencrypt_email`, `route53_hosted_zone_id`, `route53_region` are no longer gateway-config inputs, and `routes` is no longer `{}` — preprod now carries a `rollouts` route (ADR-056). — **Evidence:** `…/preprod/.../gateway-config/terragrunt.hcl:84-104` — **Proposed fix:** replace snippet with the current gateway-unit + gateway-config inputs.
  - [SEVERITY: low] "internal = false (the module default)" — still true, but now of the **`gateway`** module (`variables.tf:57`). Platform `gateway` `internal=true`, preprod `internal=false` — **verified**. — **Evidence:** `…/platform/.../gateway/terragrunt.hcl:77`; `…/preprod/.../gateway/terragrunt.hcl:79`.
  - [SEVERITY: low] "The tenant module (ADR-027) creates both policies" — tenant module **retired**; now the Environment Composition.
  - [SEVERITY: low] Risk note `restrict-route-hostnames-team-<t>` reading `teams.hcl` → now `restrict-route-hostnames-<team>-<product>-<stage>`, Composition-owned, fed by the Environment claim. — **Evidence:** `infra/modules/policy/variables.tf:288`.
  - [SEVERITY: low] cert-manager IRSA → Pod Identity (cross-cutting).
- **Decision concerns:** Decision correct and live; implementation detail drifted hard after the gateway/gateway-config split — most likely ADR in the batch to mislead an editor.

---

## ADR-030: Route53 Subdomain Delegation for Environment DNS
- **Status quoted:** `Accepted`
- **Findings:**
  - [SEVERITY: low] All structural claims **verified**: `route53_delegation` module creates only NS records; NS TTL default **172800** (`route53_delegation/variables.tf:21`); preprod `route53` + platform `route53-delegation` units exist; route53 module supports **CAA** (`route53/main.tf:11-18`); preprod zone `force_destroy=true` + CAA (`…/preprod/.../route53/terragrunt.hcl:18,21`).
  - [SEVERITY: low] "Both controllers authenticate via IRSA (ADR-018)" — cert-manager + external-dns now use **Pod Identity** (ADR-047). Per-zone scoping unchanged. — **Evidence:** `cert-manager/main.tf:107`; `external-dns/main.tf:90`.
- **Decision concerns:** none. Strongest ADR in the batch — accurate apart from IRSA wording.

---

## ADR-031: Multi-App Tenant Model
- **Status quoted:** `Accepted`
- **Findings:**
  - [SEVERITY: medium] The single supersession banner points only to **ADR-049** and frames the future as "the **v2 `Tenant` claim** (design-stage; lands with the rebuild)." Reality: the whole `teams.hcl`/`tenants`/`apps`-map surface was **removed at the v3 cutover (ADR-067/069), which is LIVE**; no `teams.hcl` exists. Unlike ADR-032, it gives no signal its mechanism is gone. — **Evidence:** no `teams.hcl`; `docs/adrs/032…:9-23`; `crossplane/.environment-api-tests/README.md:6` — **Proposed fix:** add an Implementation Status note mirroring ADR-032.
  - [SEVERITY: low] "Downstream Consumers" table describes retired plumbing — fold into the same note.
- **Decision concerns:** Decoupling idea survived into Product/Service, but the ADR reads as if `teams.hcl` is current; needs the same honest "removed at v3" note ADR-032 carries.

---

## ADR-032: PR Preview Environments
- **Status quoted:** `Accepted — **not yet implemented on the v3 delivery model** (see Implementation Status)`
- **Findings:**
  - [SEVERITY: low] Exemplary Implementation Status — correctly states the v2 `preview`/`teams.hcl`/`tenants`/`github_org`/`preview_appset` surface was **removed at v3 cutover (ADR-067/069)**; only `preview_domain` host-rewrite exists. Matches repo (`gitops/releases/` exists; no `teams.hcl`).
  - [SEVERITY: low] "ApplicationSet controller… chart version 9.5.14" — **verified** (`argocd/variables.tf:65`; `_versions.hcl:105`).
  - [SEVERITY: low] **NEEDS LIVE/OWNER VERIFICATION (external repos):** `app-alpha#24` / per-app `name-reference.yaml` (#155) not checkable here; already marked future work.
- **Decision concerns:** none — model the other tenancy ADRs should follow for amend hygiene.

---

## ADR-033: Defer vCluster Tenant Support
- **Status quoted:** `Accepted` (`Supersedes: Partially supersedes ADR-027`)
- **Findings:**
  - [SEVERITY: low] "vCluster module… upgraded to chart version **0.34.1**" — **verified** (`vcluster/variables.tf:24,30`; module present). Decision (namespace-only) accurate.
  - [SEVERITY: low] Amendment correctly notes `infra/modules/tenant` retired. Same XTenant→XEnvironment naming caveat as ADR-027 (amendment predates v3 rename). — **Evidence:** `charts/environment-api/templates/xenvironment-xrd.yaml:24`.
  - [SEVERITY: low] "The tenant module's vCluster code path remains functional" now historically false (module deleted), but the banner corrects it.
- **Decision concerns:** none. Honest, narrow ADR.

---

## Cross-cutting notes

1. **IRSA → EKS Pod Identity drift (024, 025, 026, 029, 030).** Every secrets/DNS/cert ADR here describes pod AWS auth as **IRSA (ADR-018)** — which is itself marked *Superseded by ADR-047*. Live modules (`external-secrets`, `cert-manager`, `external-dns`) all use `aws_eks_pod_identity_association` with no IRSA annotation. Wording, not architecture; a single sweep replacing "IRSA (ADR-018)" with "Pod Identity (ADR-047)" fixes all five.
2. **The `teams.hcl`/`tenant`-module world (027, 028, 029, 031, 032, 033).** This batch is pre-v3 tenancy. `infra/modules/tenant`, the `tenants` unit, and `teams.hcl` are **deleted**; provisioning is the Crossplane **`XEnvironment`** Composition (the intermediate `XTenant` was also removed). Amend quality is uneven: ADR-032 (and the 027/033 banners) handle it well; **ADR-028** (Repository Structure) and **ADR-031** (only an ADR-049 banner) still read as if `teams.hcl` is live. Per-team Kyverno policy names (`verify-images-team-*`, `restrict-route-hostnames-team-*`) are now **per-product/Composition-owned** (ADR-046/067), and several amendments name the now-renamed `XTenant` kind.
3. **The gateway/gateway-config split (029).** Highest-risk drift: NLB scheme, TLS, and DNS inputs moved out of `gateway-config` into a new `gateway` module/unit, so ADR-029's snippet and prose point at variables that no longer exist on the module they name. Decision correct and live; the *how* is wrong.
