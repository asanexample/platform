# ADR Accuracy Review — ADRs 012–022

Adversarial accuracy review against the worktree at `/Users/josh/centric/platform-adr-review` (origin/main). Evidence cited from this checkout.

---

## ADR-012: ArgoCD SSO via Dex and SAML
- **Status quoted:** `Superseded by ADR-053 / ADR-059 (Keycloak OIDC is the ArgoCD IdP)`
- **Findings:**
  - [SEVERITY: low] Status accurate and matches the index (`README.md:88`) and reality — the live argocd unit sets `dex_enabled = false` and brokers SSO through Keycloak OIDC. **Evidence:** `infra/live/aws/platform/us-east-1/platform/argocd/terragrunt.hcl:176`, lines 229–244. — **Proposed fix:** none.
  - [SEVERITY: low] Referenced `docs/runbooks/argocd-sso.md` still exists, so the reference is not broken. **Evidence:** `docs/runbooks/argocd-sso.md` present. — **Proposed fix:** none.
- **Decision concerns:** none — clean historical record with an accurate supersession note.

---

## ADR-013: Compliance Tier Model
- **Status quoted:** `Accepted`
- **Findings:**
  - [SEVERITY: low] All named Phase-1 baseline policies exist as live `ClusterPolicy` names (`require-requests-limits`, `require-workload-labels`, `require-pod-probes`, `disallow-latest-tag`, `block-public-loadbalancer`, `disallow-default-namespace`, tier-gated `require-pod-security-restricted`/`require-ro-rootfs`). Verified-correct. **Evidence:** `grep "name:" infra/modules/policy/policies-chart/templates/*.yaml`. — **Proposed fix:** none.
  - [SEVERITY: low] "The `compliance_tier` is validated by the policy module (Kyverno) with `contains([...])`" conflates layers — that is an **OpenTofu variable validation**, not a Kyverno rule. **Evidence:** `infra/modules/policy/variables.tf` compliance_tier validation block. — **Proposed fix:** reword to "validated by the `policy` module's OpenTofu variable validation" (drop "(Kyverno)").
  - [SEVERITY: low] Consistent pre-ADR-067 "tenant" terminology; the namespace label it implicitly relies on changed (see ADR-014). — **Proposed fix:** optional terminology refresh.
- **Decision concerns:** The HIPAA/PCI tier rows (dedicated cluster, isolated VPC, WAF/IDS) are an unbuilt forward spec; the ADR is honest about that. Worth flagging the model has never been exercised above `standard`.

---

## ADR-014: Kyverno as Policy Engine
- **Status quoted:** `Accepted — **Deployed (Phase 1, 2026-05-29)**. ...`
- **Findings:**
  - [SEVERITY: medium] Stale namespace label. ADR states "Tenant-targeted policies match the `platform.refplat.org/tenant` namespace label." Live module matches `platform.refplat.org/team`. **Evidence:** `infra/modules/policy/variables.tf:97`, `infra/modules/policy/policies-chart/values.yaml:37`. — **Proposed fix:** `…/tenant` → `…/team`, "Tenant-targeted" → "Environment-targeted".
  - [SEVERITY: medium] Stale source-of-truth claim. "per-tenant values (`tenant_registry_map`, `allowed_registries`) … supplied by the Terragrunt unit from `teams.hcl`." `teams.hcl` is gone repo-wide and `tenant_registry_map`/`migrated_teams` were removed from the live policy units (now per-Product derivation from the Product registry). **Evidence:** `find infra -name teams.hcl` → none; `infra/live/aws/preprod/us-east-1/platform/policy/terragrunt.hcl:107` ("inputs were removed this cutover"). — **Proposed fix:** replace with per-Product registry derivation (`verify_subjects_product`/`attest_caller_repos`).
  - [SEVERITY: low] The 2026-06-03 amendment uses superseded names: "Crossplane **Tenant** Composition" (now Environment/`XEnvironment`) and `verify-images`/`verify-attestations` (live templates are `verify-images-product`/`verify-attestations-product`). **Evidence:** `ls infra/modules/policy/policies-chart/templates/`. — **Proposed fix:** update names (or leave as dated amendment).
  - [SEVERITY: low] Verified-correct: chart `3.8.1`/app `1.18.1`; `replica_count` 3 platform / 1 preprod; Enforce on both; all four referenced architecture docs + break-glass runbook exist. **Evidence:** `_versions.hcl`, `policies-chart/Chart.yaml:6`, policy live units, `docs/architecture/*`. — **Proposed fix:** none.
- **Decision concerns:** Body is solid; staleness is concentrated in pre-ADR-067 "tenant" vocabulary and the retired `teams.hcl`/`tenant_registry_map` wiring leaking into present-tense claims.

---

## ADR-015: CIDR Allocation Strategy
- **Status quoted:** `Accepted`
- **Findings:**
  - [SEVERITY: high] The "Overlay CIDRs (Kubernetes)" table is wrong three ways and could cause a misconfiguration. (a) It lists Service CIDR `10.241.0.0/16` and DNS IP `10.241.0.10`; the real EKS service CIDR is `172.20.0.0/16` with CoreDNS at `172.20.0.10`. (b) `10.241.0.0/16` is actually **preprod's pod CIDR** — the ADR's "service CIDR" collides with a live pod range. (c) It claims overlay ranges are "shared across all clusters," but pod CIDRs are deliberately **per-cluster non-overlapping** from a reserved `10.240.0.0/14` supernet (ClusterMesh-ready). **Evidence:** `infra/live/aws/platform/us-east-1/network.hcl:7-8`, `infra/live/aws/preprod/us-east-1/network.hcl:8`, `infra/docs/06-cidr-allocation.md:87-97`. — **Proposed fix:** rewrite to pod supernet `10.240.0.0/14` with per-cluster pod CIDRs (platform `10.240/16`, preprod `10.241/16`, prod `10.242/16` reserved) and EKS service CIDR `172.20.0.0/16` (DNS `172.20.0.10`); delete "shared across all clusters."
  - [SEVERITY: medium] Prose says "Each region gets a **/21** … subdivided into 6 tiers across 3 AZs," but the implementation carves **a /24 per AZ** from the /16 (`cidrsubnet(vpc_cidr, 8, az_idx)`), then tiers within each AZ's /24 — the ADR's own newbits (e.g. `/24`+2=`/26`) only work against a /24 parent, contradicting the "/21 per region." **Evidence:** `infra/live/aws/platform/us-east-1/network.hcl:11-23`. — **Proposed fix:** "each AZ gets a /24 from the env /16; the 6 tiers are carved within each AZ's /24."
  - [SEVERITY: low] Verified-correct: AWS `/14`, platform `10.100.0.0/16`, preprod `10.101.0.0/16`, prod `10.102.0.0/16`; historical GCP `10.102/16` overlap removed and acknowledged in the risk note. **Evidence:** three `network.hcl` `vpc_cidr` values; `infra/docs/06-cidr-allocation.md:44`. — **Proposed fix:** none.
- **Decision concerns:** Strategy is sound; documentation drifted from the implemented model. Fix the Overlay table first — new-cluster onboarding reads it.

---

## ADR-016: OpenTofu over HashiCorp Terraform
- **Status quoted:** `Accepted`
- **Findings:**
  - [SEVERITY: low] Verified-correct: `terraform_binary = "tofu"` (`infra/root.hcl:3`); OpenTofu `v1.12.1`, floor `>= 1.6.0`; CI runs `tofu fmt`/`validate`. **Evidence:** `.tool-versions`, `infra/modules/aws/networking/versions.tf:2`, `.github/workflows/ci.yml:59`. — **Proposed fix:** none.
  - [SEVERITY: low] Lock-file example pins AWS `6.47.0`; module constraint is `~> 6.0` (illustrative, plausible). — **Proposed fix:** none.
  - [SEVERITY: low] Context says "Azure/GCP planned" while CLAUDE.md says they were removed (multi-cloud remains design intent). — **Proposed fix:** optional one-liner noting the scaffolding was removed.
- **Decision concerns:** none.

---

## ADR-017: Gateway API over Traditional Ingress
- **Status quoted:** `Accepted`
- **Findings:**
  - [SEVERITY: medium] Module misattribution. ADR says `gateway-config` creates **ClusterIssuer + Gateway + HTTPRoute** (with an embedded `kubernetes_manifest "gateway"`). In the repo the **ClusterIssuer and Gateway live in a separate `gateway` module** (deployed EARLY per CLAUDE.md); `gateway-config` now creates **only HTTPRoutes**. **Evidence:** `infra/modules/gateway/main.tf:9` (ClusterIssuer), `:50` (Gateway, `gatewayClassName = "cilium"`); `infra/modules/gateway-config/main.tf` only `kind = "HTTPRoute"` (lines 16, 47). — **Proposed fix:** rewrite the module section to reflect the `gateway` (ClusterIssuer+Gateway, early) vs `gateway-config` (HTTPRoutes, leaf) split.
  - [SEVERITY: low] Verified-correct: Cilium GatewayClass, the `ingress`-identity (8) `fromEntities` gotcha, per-cluster exposure (internal NLB platform / public preprod, ADR-029). — **Proposed fix:** none.
- **Decision concerns:** "leaf node with 6 upstream deps" is now only half-true (HTTPRoutes leaf; shared Gateway early).

---

## ADR-018: IRSA for Pod-Level AWS Identity
- **Status quoted:** `Superseded by ADR-047 … existing IRSA add-ons keep working until they migrate at the planned rebuild.`
- **Findings:**
  - [SEVERITY: low] Status consistent with ADR-047 in this checkout. **Evidence:** `docs/adrs/047…:44-46`, `README.md:89`. — **NEEDS LIVE/OWNER VERIFICATION:** the add-on modules (`argocd`, `cert-manager`, `external-dns`, `external-secrets`) now carry *both* an IRSA path and an `aws_eks_pod_identity_association` path; project memory claims #594 migrated platform add-ons to Pod Identity live (2026-06-24), which would contradict "migrate at the rebuild." The deployed state can't be resolved from the repo. **Evidence:** both `pod_identity` and `eks.amazonaws.com/role-arn` grep-match those four module `main.tf`s.
  - [SEVERITY: low] "Modules Using IRSA" table is a period-accurate historical snapshot; modules now support both mechanisms. ADR is retained as superseded history. — **Proposed fix:** none.
- **Decision concerns:** none — superseded record.

---

## ADR-019: External Secrets Operator for Secrets Management
- **Status quoted:** `Accepted`
- **Findings:**
  - [SEVERITY: low] Verified-correct: ESO chart `0.14.3`; `ClusterSecretStore` via separate `secret-stores` module (ADR-024); `platform/tailscale/oauth` secret path exists. **Evidence:** `_versions.hcl`, `infra/live/aws/platform/us-east-1/platform/tailscale/terragrunt.hcl:95`. — **Proposed fix:** none.
  - [SEVERITY: low] "Uses IRSA (ADR-018)" cross-references a now-superseded ADR; the `external-secrets` module carries both IRSA and Pod-Identity paths. Per ADR-047 the add-on legitimately stays IRSA until rebuild. — **Proposed fix:** add "(IRSA today; Pod Identity is the go-forward standard — ADR-047)".
  - [SEVERITY: low] "most secrets still flow through Terragrunt … rather than ExternalSecret CRDs" is consistent with the SOPS-at-parse-time model (ADR-066). — **Proposed fix:** none.
- **Decision concerns:** none.

---

## ADR-020: SSM Session Manager Bastion over SSH Bastion
- **Status quoted:** `Accepted`
- **Findings:**
  - [SEVERITY: low] Fully verified-correct: `t3.nano`; `AmazonSSMManagedInstanceCore`; Amazon Linux 2023 from SSM AMI param; egress-only SG; `scripts/eks-tunnel.sh` using `AWS-StartPortForwardingSessionToRemoteHost`; PlatformAdmin tag-scoped `ssm:StartSession` (ADR-040). **Evidence:** `infra/modules/aws/ssm-bastion/variables.tf:25`, `main.tf:36,8,87-88`, `scripts/eks-tunnel.sh:77`. — **Proposed fix:** none.
- **Decision concerns:** none — cleanest ADR in the batch.

---

## ADR-021: ArgoCD for GitOps Delivery
- **Status quoted:** `Accepted`
- **Findings:**
  - [SEVERITY: medium] Stale, in-force SSO claim. "ArgoCD authenticates users via **Dex and SAML**, integrated with AWS Identity Center (ADR-012). Group claims from SAML drive RBAC." Live unit disables Dex and uses **Keycloak OIDC** (ADR-053/059); the ADR cross-references the *superseded* ADR-012 as current. **Evidence:** `infra/live/aws/platform/us-east-1/platform/argocd/terragrunt.hcl:176` (`dex_enabled = false`), 229–244, 82. — **Proposed fix:** replace with "authenticates via Keycloak OIDC (Dex disabled; ADR-053/059)," drop/mark-historical the ADR-012 cross-ref.
  - [SEVERITY: low] "…and optionally Dex" survives the migration (Dex now off) — dated but not wrong. — **Proposed fix:** none required.
  - [SEVERITY: low] Verified-correct: single hub on platform cluster; `argocd`/`-apps`/`-clusters` live only under `infra/live/aws/platform/`; preprod spoke; chart `9.5.14`. IRSA-for-ECR carries the ADR-018/047 Pod-Identity nuance (NEEDS LIVE/OWNER VERIFICATION). **Evidence:** `find infra/live -path "*argocd*"`, `_versions.hcl`. — **Proposed fix:** none.
- **Decision concerns:** An `Accepted` ADR presenting the retired Dex/SAML path as live is the notable issue.

---

## ADR-022: DNS Architecture — Route53 with Cloudflare Delegation
- **Status quoted:** `Accepted`
- **Findings:**
  - [SEVERITY: medium] Same ClusterIssuer misattribution as ADR-017: "ClusterIssuer (configured in the `gateway-config` module)" — it now lives in the `gateway` module. **Evidence:** `infra/modules/gateway/main.tf:9`; `gateway-config/main.tf` has no ClusterIssuer. — **Proposed fix:** "configured in the `gateway` module."
  - [SEVERITY: low] Verified-correct: `route53`/`cloudflare-dns`/`external-dns` units exist; `cloudflare/dns_delegation` wired; `force_destroy`/no-`prevent_destroy` matches the rebuild posture. **Evidence:** `infra/live/aws/platform/us-east-1/platform/cloudflare-dns/terragrunt.hcl`, `_versions.hcl` module map. — **Proposed fix:** none.
- **Decision concerns:** none beyond the shared gateway/gateway-config split.

---

## Cross-cutting note

1. **Gateway/ClusterIssuer module split not reflected** (ADR-017, ADR-022). The shared Gateway + ClusterIssuer moved from `gateway-config` to a dedicated, earlier-deployed `gateway` module; `gateway-config` is now HTTPRoutes-only. Fix both together.
2. **Pre-ADR-067 "tenant" vocabulary + retired wiring leaking into present tense** (ADR-014, lightly 013): the `…/tenant` label (now `/team`), deleted `teams.hcl`, and removed `tenant_registry_map`/`migrated_teams` inputs — now factual errors about the live module.
3. **Identity-mechanism drift around superseded ADRs** (012/018): ADR-021 presents retired Dex/SAML SSO as current; ADRs 019/021 reference IRSA (superseded by ADR-047) while modules now carry both IRSA and Pod-Identity paths. The deployed IRSA-vs-Pod-Identity state for platform add-ons cannot be resolved from the repo — flagged NEEDS LIVE/OWNER VERIFICATION.

Highest blast radius: **ADR-015's Overlay CIDR table** (wrong service CIDR, a "service CIDR" that collides with preprod's live pod range, false "shared across all clusters"). Correct that first.
