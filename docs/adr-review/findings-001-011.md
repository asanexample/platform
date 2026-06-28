# ADR Accuracy Review — ADRs 001–011

Checkout: `/Users/josh/centric/platform-adr-review`. Ground truth: repo modules/units, `CLAUDE.md`, `docs/adrs/README.md`, cross-ADR consistency.

---

## ADR-001: Multi-Cloud Terragrunt Monorepo Structure
- **Status quoted:** `**Status:** Accepted`
- **Findings:**
  - [SEVERITY: medium] Presents `secrets.hcl` (gitignored) as the live secrets mechanism (layout tree, Layer-2 table "common.hcl loads secrets.hcl", closing note lines 101–102). Live mechanism is SOPS-encrypted `secrets.enc.yaml` **committed** to git (ADR-066); `secrets.hcl` is only a `TG_SOPS_BOOTSTRAP=1` fallback. — **Evidence:** `infra/live/aws/` has `secrets.enc.yaml` + `secrets.hcl.example` (no `secrets.hcl`); `infra/live/aws/common.hcl:11` `_secrets = … sops_decrypt_file(…secrets.enc.yaml)`; `.gitignore:70-73`. — **Proposed fix:** Show `secrets.enc.yaml` (SOPS, committed) as primary, `secrets.hcl` as bootstrap fallback; cross-ref ADR-066.
  - [SEVERITY: low] `_versions.hcl` = "Module source + Helm chart version pins" — verified correct. — **Evidence:** `infra/live/aws/_versions.hcl`. — **Proposed fix:** none.
- **Decision concerns:** 6-layer hierarchy + local sourcing match the repo; only the secrets layer is stale.

---

## ADR-002: AWS State Storage in S3 with Cloud-Aware Routing
- **Status quoted:** `**Status:** Accepted`
- **Findings:**
  - [SEVERITY: medium] False present-tense / internal contradiction: "Azure and GCP state **continues to use** Azure Blob Storage" (line 57) and "an **Azure outage** does not affect AWS state operations" (line 144) contradict the ADR's own Context (Azure/GCP deferred, not deployed). — **Evidence:** ADR lines 15–20 vs 57, 144; `infra/live/` has only `aws/`. — **Proposed fix:** Reword to conditional/future.
  - [SEVERITY: medium] Embedded `root.hcl` snippet (lines 67–89) is stale: shows `read_terragrunt_config(…secrets.hcl)` and `local._secrets.locals.state_bucket`/`.locals.state_role_arn`. Real file uses `yamldecode(sops_decrypt_file(…secrets.enc.yaml))` and flat accessors `local._secrets.state_bucket`/`.state_role_arn` (no `.locals.`). — **Evidence:** `infra/root.hcl:16,21` + locals block. — **Proposed fix:** Replace snippet with current SOPS block; cross-ref ADR-066.
  - [SEVERITY: low] "bootstrap's backend is migrated to S3" (121–124) is aspirational (see ADR-006); live bootstrap is still local. — **Evidence:** `state-bootstrap/terragrunt.hcl:13-22`. — **Proposed fix:** Add ADR-006's not-yet-landed caveat.
- **Decision concerns:** Per-cloud-backend rationale sound; "continues to use Azure Blob" is the main defect.

---

## ADR-003: Service Control Policy Design Philosophy
- **Status quoted:** `**Status:** Accepted`
- **Findings:**
  - [SEVERITY: high] SCP budget/attachment model stale. ADR: Platform OU has 1 direct SCP (`protect-data-and-network`) → 5 effective / 0 remaining (lines 134, 143, 153). Live attaches **3** to Platform OU (`protect-data-and-network`, `require-tagging`, `restrict-iam-users`), matching Workloads (deliberate security-audit change). — **Evidence:** `infra/live/aws/mgmt/global/organizations/terragrunt.hcl:38-42` + comment 34-37. — **Proposed fix:** Update attachment example + budget table (Platform = 3 direct / 7 effective).
  - [SEVERITY: medium] Exempt-role list stale: ADR says "in the live org these are PlatformDeployer and the Terratest CI role"; live also has `crossplane-ecr-provisioner`, `crossplane-provisioner-*`, `platform-use1-eks-karpenter-*`, `preprod-use1-eks-karpenter-*`. — **Evidence:** `organizations/terragrunt.hcl:28-32`. — **Proposed fix:** Enumerate current set or soften.
  - [SEVERITY: low] 7 default + 1 HIPAA SCP count and all 8 names verified; `DenyTeamTagTampering` correctly a statement inside `protect-data-and-network`. — **Evidence:** `scps.tf` (8 docs; `scps.tf:419 sid="DenyTeamTagTampering"`); `variables.tf:50-90`. — **Proposed fix:** none.
- **Decision concerns:** Override + OU-attachment rationale sound; stale Platform-OU budget understates current coverage.

---

## ADR-004: AWS Account Management Strategy
- **Status quoted:** `**Status:** Accepted`
- **Findings:**
  - [SEVERITY: low] Dual-mode design, `create_organization` default false, live uses `true` — verified. — **Evidence:** `organizations/variables.tf:7-11`; `organizations/terragrunt.hcl:16`. — **Proposed fix:** none.
  - [SEVERITY: low] Account/OU example matches live `accounts` map. — **Evidence:** `organizations/terragrunt.hcl:52-57`. — **Proposed fix:** none.
- **Decision concerns:** none — accurate.

---

## ADR-005: Organizational Unit Hierarchy Design
- **Status quoted:** `**Status:** Accepted`
- **Findings:**
  - [SEVERITY: high] **"Test Account Placement" rationale now false.** ADR (lines 209–216, 241–244): Test sits in Platform OU so it inherits only root SCPs + `protect-data-and-network` and **not** Workloads `require-tagging`/`restrict-iam-users`. Live attaches both to the Platform OU, so Test *does* inherit them; the sandbox is unblocked via `exempt_roles` instead. — **Evidence:** `organizations/terragrunt.hcl:40` + comment 34-37. — **Proposed fix:** Rewrite: Platform OU now carries the same 3 SCPs; sandbox unblocked via exempt IaC roles.
  - [SEVERITY: high] Inheritance diagram + budget stale for Platform OU ("5 SCPs (4 inherited + 1 direct)" / "1 direct, 4 slots remaining", lines 133–136, 163). Live = 3 direct / 7 effective. — **Evidence:** `organizations/terragrunt.hcl:40`. — **Proposed fix:** Update diagram + budget list.
  - [SEVERITY: low] OU hierarchy + account placement otherwise match live. — **Evidence:** `organizations/terragrunt.hcl:44-57`. — **Proposed fix:** none.
- **Decision concerns:** Two-branch design sound, but the SCP-coverage prose is out of date post-audit; a reader could wrongly think Test/Platform lack tag/IAM-user enforcement.

---

## ADR-006: State Bootstrap Pattern
- **Status quoted:** `**Status:** Accepted`
- **Findings:**
  - [SEVERITY: medium] The Decision narrative presents migrate-to-S3 as implemented (State-Lifecycle section, comparison table "Local (first apply) → S3", Deploy Order "Migrates its own state into the new S3 bucket"), but it is **not** implemented: live unit is permanently local, and the unit README frames local as **intentional**. The ADR's own caveat (144–145) admits it's a follow-up, and its claim that "the unit README documents the procedure" is false — the README says the opposite. — **Evidence:** `state-bootstrap/terragrunt.hcl:13-22` (`backend = "local"`); unit `README.md:20` ("intentional … it cannot use that bucket itself"). — **Proposed fix:** Demote migrate-to-S3 to a marked follow-up (or implement); fix the README claim.
  - [SEVERITY: low] Module facts verified (2 resources, `count = var.create ? 1 : 0`, import addresses `aws_s3_bucket.state[0]`/`aws_dynamodb_table.locks[0]`, unit path). — **Evidence:** `state_bootstrap/main.tf:1-35`. — **Proposed fix:** none.
- **Decision concerns:** Pattern sound, but ~60% of the doc describes a non-existent migrated end state contradicted by the unit README; the single status note is easy to miss.

---

## ADR-007: Platform IAM Role Model
- **Status quoted:** `**Status:** Accepted (DeveloperAccess refined into per-team roles in ADR-039; PlatformAdmin rescoped to operate-not-author in ADR-040)`
- **Findings:**
  - [SEVERITY: medium] Stale source-of-truth: per-team `DeveloperAccess-<team>` roles/access-entries/RBAC "generated from **`teams.hcl`** (the single source of truth)" (lines 70, 120–121). `teams.hcl` no longer exists (registries-as-single-source, ADR-061/063/067; CLAUDE.md "teams.hcl is retired"), and DeveloperAccess is **not currently provisioned** (#647). — **Evidence:** `find … teams.hcl` → no matches; CLAUDE.md IAM-roles table. — **Proposed fix:** Replace `teams.hcl` with the registries / point to ADR-039; note DeveloperAccess not yet provisioned.
  - [SEVERITY: low] PlatformDeployer "Platform, PreProd, Test" + OAAR break-glass consistent with CLAUDE.md; status header correctly flags ADR-039/040. — **Evidence:** CLAUDE.md; README:90-91. — **Proposed fix:** none.
- **Decision concerns:** Largely superseded (noted). Residual risk: the `teams.hcl` generation claim implies DeveloperAccess is built when it isn't.

---

## ADR-008: Cilium as Cross-Cloud CNI
- **Status quoted:** `**Status:** Accepted`
- **Findings:**
  - [SEVERITY: high] **Live AWS datapath is overlay (cluster-pool IPAM + VXLAN), not ENI native routing.** Contradicts the AWS-column table (IPAM=ENI/Routing=Native/Masquerade=`ens+`), the "AWS ENI Mode" section ("pod gets an IP from the VPC subnet via ENI secondary IPs … without encapsulation"), the `egressMasqueradeInterfaces = ens+` "must set / else lose egress" claim, and the Risk ("ENI mode ties pod IP allocation to VPC subnet capacity … mitigated by the /26 kubernetes subnet"). Pods draw from a dedicated `pod_cidr` (10.240.0.0/16, "non-routable; VXLAN-encapsulated"), not the /26 node subnet. — **Evidence:** `cilium/variables.tf` defaults `ipam_mode="cluster-pool"` (33-37), `routing_mode="tunnel"` (43-47), `tunnel_protocol="vxlan"` (53-57), `egress_masquerade_interfaces=""` (89-93); platform + preprod cilium units set only `cloud_provider="aws"`/`pod_cidr` with comment "Overlay datapath (cluster-pool IPAM + VXLAN) … Override here (e.g. ipam_mode=\"eni\") to use native"; platform `network.hcl` `pod_cidr="10.240.0.0/16"`. — **Proposed fix:** Rewrite the AWS column / "AWS ENI Mode" section / masquerade + subnet-exhaustion risk to reflect overlay (cluster-pool/VXLAN); present ENI as a non-default mode.
  - [SEVERITY: low] Verified: shared `infra/modules/cilium/` with `cloud_provider` (default aws); `kubeProxyReplacement=true`; chart 1.19.4 (`_versions.hcl:104` + `helm_chart_version` default); BYOCNI `bootstrap_self_managed_addons=false`; Gateway-API `ingress`-identity guidance (datapath-independent, valid). — **Evidence:** `cilium/variables.tf:12-16,195-199`; `cilium/main.tf:43`. — **Proposed fix:** none.
- **Decision concerns:** Cross-cloud-uniform-CNI decision sound, but the doc describes an AWS datapath the platform does not run — highest-impact inaccuracy in the batch (misleads on subnet sizing, egress masquerade, pod-IP capacity).

---

## ADR-009: EKS Component Separation
- **Status quoted:** `**Status:** Accepted`
- **Findings:**
  - [SEVERITY: low] Four-unit split (`eks → cilium → node-groups → eks-addons`), module mapping, `bootstrap_self_managed_addons=false`, `dependency`+`mock_outputs`, reverse-order destroy all verified. — **Evidence:** module dirs exist; platform cilium unit `dependency "eks"` w/ `mock_outputs`. — **Proposed fix:** none.
- **Decision concerns:** none — accurate, matches the live DAG.

---

## ADR-010: Private-Only EKS API Endpoint
- **Status quoted:** `**Status:** Accepted`
- **Findings:**
  - [SEVERITY: low] EKS module defaults `endpoint_public_access=false`/`endpoint_private_access=true` — verified. — **Evidence:** `aws/eks/variables.tf:29-39`. — **Proposed fix:** none.
  - [SEVERITY: low] "Both platform and preprod private-only" — IaC confirms; running endpoint state is **NEEDS LIVE/OWNER VERIFICATION** but consistent with CLAUDE.md. — **Evidence:** module default + CLAUDE.md. — **Proposed fix:** none.
  - [SEVERITY: low] Access paths (Tailscale `10.100.0.0/16`/split-DNS `10.100.0.2`; `scripts/eks-tunnel.sh` 8443 fallback; platctl unlock/lockdown) match repo + CLAUDE.md. — **Evidence:** `scripts/eks-tunnel.sh`; `network.hcl`. — **Proposed fix:** none.
- **Decision concerns:** none.

---

## ADR-011: Tailscale Operator for Private Cluster Access
- **Status quoted:** `**Status:** Accepted`
- **Findings:**
  - [SEVERITY: low] Verified: subnet-router operator; per-cluster CIDRs (platform `10.100.0.0/16`, preprod `10.101.0.0/16`); `TS_USERSPACE=true` ProxyClass; `split_dns`→`10.100.0.2`; cloud-agnostic module; SSM fallback. — **Evidence:** `tailscale/main.tf:63`, `variables.tf:56`, `README.md:124`; preprod `network.hcl`. — **Proposed fix:** none.
  - [SEVERITY: low] Split-DNS example `*.eks.amazonaws.com` vs live region-scoped `us-east-1.eks.amazonaws.com`. Cosmetic. — **Evidence:** live tailscale unit README:20. — **Proposed fix:** optional note.
  - [SEVERITY: low] "Tailscale free tier limits to 3 users" — external vendor fact, has since changed; **NEEDS OWNER VERIFICATION**. — **Proposed fix:** soften to "current free-tier cap."
  - [SEVERITY: low] OAuth secret path `platform/tailscale/oauth` plausible but exact name **NEEDS OWNER VERIFICATION**. — **Evidence:** `tailscale/README.md:3`. — **Proposed fix:** none unless differs.
- **Decision concerns:** none.

---

## Cross-cutting note

1. **"Multi-cloud-ready / AWS-first" framing leaks stale present-tense Azure/GCP claims** — ADR-002 ("Azure state *continues to use* Azure Blob", "an Azure outage…") is the worst; ADR-001/008 handle it cleanly. Worth sweeping all "continues to / uses" present-tense claims about undeployed clouds.
2. **Foundational ADRs (001–003, 005–008) drift from the live config as the platform hardened.** Highest-impact: Cilium datapath (ADR-008 says ENI/native; live overlay/VXLAN — high); Platform-OU SCP coverage + Test-account placement rationale (ADR-003/005 predate the audit change attaching `require-tagging`/`restrict-iam-users` to Platform — high); bootstrap migrate-to-S3 never implemented (ADR-006 — medium); secrets mechanism `secrets.hcl`→SOPS `secrets.enc.yaml` (ADR-066) cited as current in ADR-001/002/004/007 (medium). None of these cross-reference ADR-066 where they describe the secrets layer.
