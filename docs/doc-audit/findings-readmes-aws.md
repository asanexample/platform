# Documentation Audit — infra/modules/aws/*/README.md (22 modules)

Checkout @ origin/main. Clusters parked; verification against repo only. All 22 modules have a README (none missing); `cost-allocation-tags` also present + accurate.

## infra/modules/aws/cloudtrail/README.md — accurate

## infra/modules/aws/cost-allocation-tags/README.md — accurate

## infra/modules/aws/cross-vpc-dns/README.md — accurate

## infra/modules/aws/ecr/README.md

- [SEVERITY: medium] Inputs table omits `tag_mutability_exclusion_filters` (default `["sha256-*"]`, max-5 validation). — **Evidence:** `variables.tf:21-30`. — **Fix:** regenerate terraform-docs.
- [SEVERITY: medium] Silent on the `IMMUTABLE_WITH_EXCLUSION` cosign feature (#114). — **Evidence:** validation `variables.tf:16-19`; `main.tf:18-24`. — **Fix:** document the exclusion mode. (Repo-naming `team-<team>/<product>-<svc>` correct.)

## infra/modules/aws/eks/README.md

- [SEVERITY: high] Inputs table documents `endpoint_public_access` default `true`; code default is `false` (private-only, ADR-010). — **Evidence:** `README.md:130` vs `variables.tf:38`. — **Fix:** regenerate the TF_DOCS block.
- [SEVERITY: medium] Stale short descriptions for `endpoint_public_access`/`public_access_cidrs` drop the current ADR-010 guidance. — **Fix:** same regen. (Verified: `API_AND_CONFIG_MAP`, `kubernetes_version` 1.35, BYOCNI.)

## infra/modules/aws/eks-addons/README.md

- [SEVERITY: high] Entire `create_default_storageclass` / gp3 default-StorageClass feature undocumented (input + `kubernetes_storage_class_v1.gp3` resource + prose). — **Evidence:** `variables.tf:39-43`, `main.tf:96-117`. — **Fix:** regenerate docs + Notes bullet.
- [SEVERITY: medium] Providers/Requirements omit the `kubernetes` provider. — **Evidence:** `versions.tf:8-11`. — **Fix:** regenerate.
- [SEVERITY: low] Addon IRSA not flagged as legacy under the Pod-Identity standard (intentional, clarity nit).

## infra/modules/aws/eks-node-group/README.md

- [SEVERITY: high] `single_az` input entirely absent (pins all node groups to one AZ — no AZ resilience). — **Evidence:** `variables.tf:32-36`, `main.tf:124-126`. — **Fix:** regenerate docs + Notes on single-AZ cost profile.
- [SEVERITY: medium] Documented `node_groups` object omits `max_pods` (AL2023 NodeConfig). — **Evidence:** `variables.tf:24-27`, `main.tf:90-105`. — **Fix:** regenerate.
- [SEVERITY: medium] Silent on the launch template's encrypted gp3 root volume (satisfies `DenyUnencryptedEbsOnLaunch`). — **Evidence:** `main.tf:68-78`. — **Fix:** add a sentence.
- [SEVERITY: low] terraform-docs "No requirements" artifact; stale in-code comment `main.tf:62` says "IRSA".

## infra/modules/aws/eks-pod-identity/README.md

- [SEVERITY: low] README `associations` description is *more current* than source — README says "teams.hcl retired" but `variables.tf:16` still says "from teams.hcl"; a docs regen would REVERT the README to stale text. — **Fix:** update `variables.tf` description so regen stays correct.
- [SEVERITY: low] terraform-docs "No requirements" artifact.

## infra/modules/aws/github_oidc/README.md

- [SEVERITY: medium] Thumbprint rationale inaccurate — README says all-`f`s fine because "AWS validates the certificate chain"; real reason (code comment): AWS no longer validates GitHub OIDC thumbprints (since July 2023); dummy value required by API. — **Evidence:** `main.tf:44-45` vs `README.md:110`. — **Fix:** reword to match the code.
- [SEVERITY: low] Example "One role per repo/team" reflects older per-team framing (current = per-Product). Module is generic, so module-level-accurate.

## infra/modules/aws/iam_roles/README.md

- [SEVERITY: low] Presents `DeveloperAccess` as provisioned; per ADR-039/#647 it's design intent only — illustrative but could mislead.
- [SEVERITY: low] PlatformAdmin example attaches `AmazonEKSClusterPolicy` (odd for a kubectl-operator role). terraform-docs "No requirements" artifact.

## infra/modules/aws/identity_center/README.md — accurate

## infra/modules/aws/karpenter/README.md — accurate (v1 APIs, named `default`, no stale "Provisioner" terms, ADR-078 resolves)

## infra/modules/aws/networking/README.md

- [SEVERITY: high] README documents three **required** inputs — `environment`, `region_abbv`, `workload` — that **do not exist** in the module, in the TF_DOCS table AND in EVERY usage example (`README.md:13-16,60-62,74-76,100-102,130-132`). Copy-pasting any example fails (`An argument named "environment" is not expected here`). — **Evidence:** `variables.tf` declares 15 vars, none of these three. — **Fix:** strip the three vars from all examples and regenerate terraform-docs.
- [SEVERITY: low] Undocumented `kubernetes.io/cluster/<name> = shared` discovery tag on subnets. — **Evidence:** `main.tf:101-113`.

## infra/modules/aws/organizations/README.md

- [SEVERITY: medium] Note claims "Organization, OUs, **and accounts** have `prevent_destroy`"; accounts do **not** — only `close_on_deletion = false` + `ignore_changes=[role_name]`. — **Evidence:** `main.tf:63,75,84` vs `:96`. — **Fix:** scope `prevent_destroy` to org + OUs only.
- [SEVERITY: low] Verified-correct: README documents **module defaults** (`exempt_roles=["OrganizationAccountAccessRole"]`, Platform-OU `["protect-data-and-network"]`). The "7 exempt roles / 3 Platform-OU SCPs" are **live-unit** values, not module defaults — not README drift here (it IS drift in the architecture/compliance docs).

## infra/modules/aws/route53/README.md — accurate

## infra/modules/aws/route53_delegation/README.md — accurate

## infra/modules/aws/s3/README.md

- [SEVERITY: medium] Claims `reader_role_arns` are "assembled at the terragrunt unit from `teams.hcl`" — `teams.hcl` is **retired**. — **Evidence:** README line 13; no such file; live units note it retired. — **Fix:** replace with registry-derived (per-Product) wording.
- [SEVERITY: low] No live unit consumes `modules/aws/s3` — qualify as intended pattern.

## infra/modules/aws/sns-notifications/README.md — accurate

## infra/modules/aws/sops-kms/README.md

- [SEVERITY: low] No Outputs section, but the module exposes 4 (`key_arn` is load-bearing for `.sops.yaml`). — **Evidence:** `outputs.tf:1-19`. — **Fix:** add an Outputs section.

## infra/modules/aws/ssm-bastion/README.md — accurate

## infra/modules/aws/state_bootstrap/README.md — accurate

## infra/modules/aws/transit-gateway/README.md — accurate

---

## Cross-cutting note

1. **Stale terraform-docs is the dominant root cause.** The three highest-impact findings (eks `endpoint_public_access` default `true`→`false`, networking's three phantom required vars, eks-addons/eks-node-group missing inputs+resources) are all "code changed, `terraform-docs` not re-run." A single repo-wide `terraform-docs` regen fixes the high/medium drift in eks, eks-addons, eks-node-group, ecr, networking at once, plus the cosmetic "No requirements" artifacts. **Recommend a pre-commit/CI check that fails on stale terraform-docs.**
2. **`teams.hcl` retirement incompletely propagated** — s3 README and the upstream `eks-pod-identity/variables.tf` description still reference it (the pod-identity README is *ahead* of its own source — fix the source or regen reintroduces stale text).
3. **Module READMEs vs live-unit values:** organizations correctly documents defaults; the "7 exempt / 3 SCP" drift lives in the architecture/compliance docs, not here. The real organizations README bug is the `prevent_destroy`-on-accounts overclaim.
4. No broken cross-links in any of the 22 modules.
