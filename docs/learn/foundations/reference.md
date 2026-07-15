# Learn: Foundations — reference

A lookup table for the foundations, not a walkthrough. The [orientation](orientation.md) builds the model;
the deep dives at the bottom go layer by layer. Every fact here is checked against the code and the live
clusters.

## Pinned versions (`/.tool-versions` + module pins)

| Component | Version | Notes |
| --- | --- | --- |
| OpenTofu | **1.12.1** | the provisioning engine (`terraform_binary = "tofu"`) |
| Terragrunt | **1.0.7** | the DRY orchestrator (v1.x CLI: `run --all`, `hcl fmt`) |
| Kubernetes / EKS | **1.35** | module default; live units don't override |
| Cilium | **1.19.4** | pinned in `infra/live/aws/_versions.hcl`; canonical |
| kubectl | 1.35.5 | tracks cluster minor (±1 skew), not latest |
| helm | 3.21.0 | CLI is debug-only; installs go through the TF helm provider |
| descheduler | 0.35.1 | v0.35 line = k8s 1.35 compat |

## The AWS estate

- **Accounts (5):** management (governance-only: org, SCPs, TF state backend) · platform (**hub**: shared
  services) · preprod + prod (**spokes**: env clusters + tenant workloads) · test (Terratest sandbox).
- **OU tree:** root (mgmt, no OU) → `Platform` OU {platform, test} · `Workloads` OU {`Preprod`, `Prod`,
  `Regulated` (empty, HIPAA staged)}.
- **Why accounts are the *hard* boundary:** a separate security + billing principal enforced by AWS; a
  credential in one account can't address another without an explicit cross-account role trust. Namespaces /
  IAM / Kyverno are *soft* boundaries inside one trust domain.

### SCPs — 8 attached (`infra/modules/aws/organizations/scps.tf`)

A **ceiling, not a grant**, enforced above the account (even root can't escape). Effective perm =
intersection(SCPs, IAM). `baseline-guardrails` (deny leave-org / root actions / region changes) ·
`protect-security-services` (can't stop CloudTrail/GuardDuty/Config) · `enforce-encryption` (no unencrypted
EBS/RDS/S3, IMDSv2 required) · `deny-regions` · `protect-data-and-network` (incl. **`DenyTeamTagTampering`** →
un-forgeable per-team ownership) · `require-tagging` · `restrict-iam-users` (force federation) ·
`hipaa-eligible-services` (optional, off). AWS's `FullAWSAccess` is the 8th. **Gotcha:** a new automation
role often needs an explicit **exempt-role** entry (org-level) or it 403s on tagging/region actions.

### IAM roles

| Role | Account | Verb |
| --- | --- | --- |
| **PlatformDeployer** | platform, preprod, test | **deploy** — Terragrunt apply + Helm/K8s exec-auth |
| **PlatformAdmin** | platform, preprod | **operate, not author** — kubectl debug/exec/drain/restart; read-only AWS minus secret-exfil denies |
| **TerraformStateAccess** | management | **state** — S3 state bucket + `terraform-locks` DynamoDB only |
| **OrganizationAccountAccessRole** | all | **break-glass** — audited emergency admin |
| **DeveloperAccess-\<team\>** | preprod (design) | per-team kubectl — **designed, not built** (only the in-cluster RoleBinding exists) |

Cross-account chain: `aws sso login` (mgmt) → assume **PlatformDeployer** in target → state via
**TerraformStateAccess** (mgmt). kubectl: assume **PlatformAdmin** → `aws eks get-token` → API over Tailscale.

## Infrastructure as code

- **Split:** `infra/modules/` (reusable, no provider blocks) vs `infra/live/aws/` (env-specific units).
- **Config cascade** (each fact in one layer): `root.hcl` → `common.hcl` → `env.hcl` → `region.hcl` /
  `network.hcl` → `workload.hcl` → `terragrunt.hcl`. `_base.hcl` loads all layers (`find_in_parent_folders` +
  `read_terragrunt_config`) and re-exposes via `include "base" { expose = true }` → `include.base.locals.*`.
  **Safety asserts:** dir-vs-env + account-ID match, or the plan refuses (`SAFETY:`).
- **State:** S3 bucket + `terraform-locks` DynamoDB in mgmt, via `TerraformStateAccess`; key = the unit's
  relative path (per-unit isolation).
- **SOPS:** `secrets.enc.yaml` committed encrypted (KMS `alias/platform-sops`), decrypted in-memory at
  plan-time; `TG_SOPS_BOOTSTRAP=1` reads a local plaintext fallback for greenfield.

## Networking

- **VPC:** one module, 3 topologies via toggles (private = IGW+NAT [default] · public = IGW no NAT ·
  airgapped = neither). 6 subnet tiers/AZ × 3 AZ = 18: kubernetes /26, endpoints /26, firewall /26, services
  /27, public /28, transit /28. Free S3 gateway endpoint + interface endpoints (secretsmanager/ssm/sts/kms)
  keep AWS-API traffic off the internet. Flow logs on.
- **CIDR:** cloud `/14` → env `/16` (platform `10.100`, preprod `10.101`, prod `10.102`) → tiers via
  `cidrsubnet(cidrsubnet(vpc,8,az),newbits,netnum)`. **Non-overlapping is mandatory** (TGW routing). Pod CIDR
  = separate non-routable overlay (`10.240.0.0/14`; VXLAN); Service CIDR `172.20.0.0/16` (Cilium-handled).
- **Transit Gateway:** hub in platform, shared to spokes via **RAM**; dedicated `/28` transit subnets hold
  the ENIs; hub-and-spoke scales linearly (vs peering's N²). Live: `tgw-0e42…`, 2 attachments.
- **Cross-VPC DNS:** EKS-managed private zones can't be shared, so the platform maintains its own. 3
  `dns_method` modes: `phz` (custom PHZ + dynamic ENI lookup, cheap, chosen) · `resolver_outbound` ·
  `resolver_inbound` (Route53 Resolver endpoints, ~$365/mo). The ENI-lookup script **fails loud**.

## The cluster

- **Private-only API:** `endpointPublicAccess: false` (module default false = fail-safe), private true.
  Verified live both clusters.
- **BYOCNI four-unit build (Cilium-first):** `eks` → `cilium` → `node-groups` → `eks-addons`, separate units
  because `bootstrap_self_managed_addons = false` ships no CNI/kube-proxy — a pod (CoreDNS) can't get an IP
  until Cilium is up. Destroying `cilium` alone = cluster-wide outage.
- **Cilium/eBPF:** `kubeProxyReplacement: true` (mandatory — no kube-proxy exists; eBPF hash-map Service LB
  vs iptables linear chains). VXLAN overlay, `cluster-pool` IPAM. Hubble TLS via `helm` method (avoids
  cert-manager chicken-and-egg). **Gateway ingress identity:** gateway→pod traffic wears Cilium's reserved
  **`ingress` identity (8)** — namespace policy must `fromEntities: ["ingress"]`, not an IP/CIDR match.

## Compute

- **System node group:** fixed floor (`t4g.xlarge`, desired 2 / max 3, Graviton) — holds Karpenter, CoreDNS,
  Cilium operator, the standing stack. Changing `instance_types` is ForceNew (a ~3-min hub blip).
- **Karpenter:** instance-flexible NodePool (arm64, bin-pack, consolidate); both clusters run
  `WhenEmptyOrUnderutilized` + `consolidateAfter: 15m` (not the module's `1m` default — a shorter value
  races the Cilium-first startup taint below and Karpenter deletes its own freshly-provisioned node as
  "empty" before its intended pod ever lands). Auth = Pod Identity. **Cilium-first startup taint**
  `node.cilium.io/agent-not-ready`. **≥8 GiB floor** (DaemonSet slab ~3.2 GiB). **SCP exemption mandatory**
  (per-cluster anchored `*-karpenter-*`).
- **Workload autoscaling (HPA):** every scaffolded Service ships a **default HPA** (`k8s/base/hpa.yaml`,
  `autoscaling/v2`, targets the Argo Rollout, CPU 70%; `min 1`/`max 10`, prod overlay `min 2`/`max 20` for
  the prod replica floor; metrics-server the CPU source) — elastic by construction, opt out not in. **The closed
  loop** (live): HPA adds pods → they go Pending → Karpenter provisions a right-sized node
  → load drops → HPA scales pods down → Karpenter consolidates the idle node away. KEDA (event-driven)
  deferred until first needed.
- **Descheduler:** `LowNodeUtilization` CronJob (platform 40/70% q15m, preprod 50/70% q10m); `nodeFit: true`,
  respects PDBs, skips system-critical. Fixes post-unpark single-replica pile-up.

## Ingress & access

- **Ingress flow:** Route53 (ALIAS) → **NLB** → **Cilium Envoy** (TLS terminate) → **HTTPRoute** (Host) →
  ClusterIP → Pod. `gateway` module (ClusterIssuer + Gateway, early) + `gateway-config` (HTTPRoutes, leaf).
- **NLB scheme:** `internal = true` (platform, Tailscale-only) vs `false` (preprod, public). One knob.
- **TLS/DNS:** cert-manager (Let's Encrypt **DNS-01**, one `*.<domain>` wildcard) + external-dns (watches
  Gateway *routes*, not Ingress; `txtOwnerId` per cluster). Both auth via Pod Identity. Hostnames
  derive-and-inject (`<product>-<team>-<stage>.<domain>`); authz is per-product Kyverno.
- **Access:** Tailscale subnet router (advertises VPC CIDR; split-DNS to the in-VPC resolver; **userspace
  mode** so it doesn't fight Cilium's eBPF for the kernel routing table). SSM tunnel (`scripts/eks-tunnel.sh`,
  bastion independent of EKS) = fallback. Public endpoint toggled *only* by `platctl` during a full rebuild.

## Gotchas (foundational)

- `SAFETY:` apply refusal → `_base.hcl` dir/account mismatch (the guard working).
- Automation `AccessDenied` on tag/region → an SCP above the account; needs an org-level exempt-role.
- `upstream connect error` with DNS/TLS fine → missing `fromEntities: ["ingress"]` (Cilium identity 8).
- `kubectl` timeout on Tailscale → split-DNS resolving before the subnet route exists (bootstrap).
- One node overloaded post-unpark → scheduler-never-moves-pods; the descheduler's job.

## Go deeper

Deep dives: [account model](deep-dive-the-account-model.md) · [IaC](deep-dive-infrastructure-as-code.md) ·
[networking](deep-dive-networking.md) · [cluster & Cilium](deep-dive-the-cluster.md) ·
[nodes, scaling & access](deep-dive-nodes-scaling-access.md). Substrate:
[OpenTofu](https://opentofu.org/docs/) · [Terragrunt](https://terragrunt.gruntwork.io/docs/) ·
[Cilium](https://docs.cilium.io/) · [Gateway API](https://gateway-api.sigs.k8s.io/) ·
[AWS multi-account](https://docs.aws.amazon.com/whitepapers/latest/organizing-your-aws-environment/organizing-your-aws-environment.html).
