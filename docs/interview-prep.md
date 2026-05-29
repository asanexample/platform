# Technical Interview Prep: Infrastructure as Code Design

Reference document mapping the platform's architecture to expected interview topics.

---

## 1. Structuring IaC across multiple teams and environments

**What we built:**

- **Three-layer separation**: reusable modules (`infra/modules/`), cloud-specific
  modules (`infra/modules/aws/`, `azure/`), and live environment configs
  (`infra/live/aws/{platform,preprod,prod}/`). Modules are DRY; live configs are
  thin wrappers that set inputs.

- **Terragrunt config hierarchy** (`root.hcl` → `_base.hcl` → unit
  `terragrunt.hcl`): environment, region, account ID, tags, and provider config
  are inherited — not repeated. Adding a new environment is copying a directory
  and changing a few locals.

- **Dependency DAG** across units: `eks → cilium → node-groups → tenants →
  argocd-apps`. Terragrunt resolves this automatically with `dependency` blocks.
  Each unit is independently plannable/applyable.

- **Multi-cloud by design**: shared modules (cilium, argocd, tenant) use a
  `cloud_provider` variable. Cloud-specific logic lives in cloud-specific
  modules. The same tenant model works on EKS and AKS.

**Key talking point:** The module/live split enforces a contract — module authors
define the interface, platform consumers just set inputs. This scales because
teams don't need to understand the module internals.

---

## 2. Remote state management

**What we built:**

- **S3 + DynamoDB** in the management account (<MGMT_ACCOUNT_ID>) with a dedicated
  `TerraformStateAccess` IAM role. Every environment's state is stored in the
  same bucket but isolated by key path
  (`{env}/{region}/{workload}/{unit}/terraform.tfstate`).

- **Locking via DynamoDB** — prevents concurrent applies. Terragrunt's
  `remote_state` block in `root.hcl` configures this once; all units inherit it.

- **Cross-account state access**: the deployer role in each account assumes
  `TerraformStateAccess` in management. No credentials in state files — OIDC/SSO
  everywhere.

- **State isolation by path, not by bucket**: simpler to manage (one bucket, one
  lock table), but each unit has its own state file. A bad apply to `tenants/`
  can't corrupt `eks/` state.

**Key talking point:** State is the most dangerous part of IaC — it contains
secrets, it's the source of truth for what exists. Our approach isolates by
environment path, locks concurrency, and restricts access to a purpose-built role
rather than broad admin credentials.

---

## 3. Handling manually-created infrastructure

**What we built:**

- **`tofu import`** for brownfield resources. The IAM Identity Center SAML app
  for ArgoCD SSO was created manually (Terraform AWS provider doesn't support
  custom SAML apps) — we documented this in ADR-012 rather than pretending it was
  automated.

- **Break-glass roles** (`OrganizationAccountAccessRole`) retained for manual
  intervention but explicitly documented as break-glass only, not day-to-day.

- **`bootstrap_self_managed_addons = false`** on EKS: we acknowledged the
  platform's BYOCNI pattern means some things (Cilium) must be deployed in a
  specific order that doesn't fit the cloud provider's default. Rather than
  fighting it, we separated concerns into ordered units.

**Key talking point:** The honest answer is you handle it pragmatically — import
what you can, document what you can't automate, and draw a clear line between
"managed by code" and "managed manually with a runbook." The worst outcome is a
resource that *looks* managed but isn't.

---

## 4. Self-service without sprawl

**What we built:**

- **`teams.hcl` as the single self-service interface**: a team adds 5 lines to
  one file and gets a namespace, resource quotas, network policies, ECR repo,
  OIDC trust, and ArgoCD Application. They don't touch Terraform modules.

- **Multi-app model** (ADR-031): teams own multiple apps without duplicating team
  config. Adding an app is a 5-line change in `teams.hcl`.

- **ArgoCD GitOps**: teams own their app manifests in their own repos. The
  platform provides the deployment pipeline (ApplicationSet, ECR, OIDC) — teams
  just push code and manifests.

- **PR preview environments** (ADR-032): fully automated ephemeral deployments.
  No platform team involvement — open a PR, get a preview URL.

- **Guardrails that prevent sprawl**: ResourceQuotas cap resource consumption per
  team. AppProject whitelists restrict what resource kinds teams can deploy.
  NetworkPolicies enforce isolation by default. Teams can't create namespaces,
  CRDs, or cluster-scoped resources.

**Key talking point:** Self-service is a product design problem, not just a
tooling problem. The interface matters — `teams.hcl` is readable by anyone,
doesn't require Terraform knowledge, and the blast radius of a bad change is
bounded to one team's namespace.

---

## 5. Compliance guardrails at scale

**What we built:**

- **SCPs** at the AWS Organization level (ADR-003): deny destructive actions
  (leaving the org, disabling CloudTrail, deleting VPC flow logs) regardless of
  IAM permissions.

- **Compliance tier model** (ADR-013): `compliance_tier` in `workload.hcl` drives
  infrastructure controls — standard (shared cluster), HIPAA (dedicated cluster,
  CMK), PCI (CDE segmentation, WAF required). The tier is tagged on every
  resource for audit queries.

- **NetworkPolicy-by-default**: every tenant namespace starts with default-deny
  ingress. Teams must explicitly allow traffic. Cilium enforces at the eBPF
  level — no iptables bypass.

- **IAM role model** (ADR-007): purpose-built roles (PlatformAdmin,
  PlatformDeployer, DeveloperAccess) with least-privilege. No shared admin
  credentials. Cross-account access via role assumption, not credential sharing.

- **CloudTrail** for secrets audit logging. ECR tag immutability (ADR-028)
  prevents image tag overwriting.

- **Policy as code** intent via Kyverno (ADR-014) — not yet fully deployed but
  the module and architecture are in place.

**Key talking point:** Compliance guardrails work best when they're invisible to
developers. SCPs enforce at the API level — no one can opt out. ResourceQuotas
enforce at the scheduler level. NetworkPolicies enforce at the kernel level. The
developer doesn't need to think about compliance; the platform makes
non-compliant configurations impossible.

---

## 6. Non-technical: adoption, buy-in, change management

**What we demonstrated through the platform's design:**

- **Progressive complexity**: teams start with the simplest path (`teams.hcl` + a
  manifest directory). They don't need to learn Terraform, Terragrunt, or Cilium.
  The platform abstracts the hard parts.

- **Documentation as a product**: ADRs explain *why*, not just *what*. Runbooks
  are step-by-step. The onboarding guide gets someone to their first deploy in 30
  minutes. This is how you get buy-in — by making the right path the easy path.

- **Escape hatches**: `resource_quota` overrides, custom Helm values passthrough
  on modules, app-specific config in `teams.hcl`. Teams aren't locked in — they
  can customize within the guardrails.

- **Decision records build trust**: 33 ADRs documenting every significant choice,
  alternatives considered, and consequences. When someone asks "why not X?", the
  answer is in the ADR, not in someone's head.

- **Dog-fooding the workflow**: the demo app (app-alpha) exercises the full
  pipeline end-to-end. When onboarding a team, you can point at a working
  example, not a README.

**Key talking point:** The biggest risk in IaC adoption isn't tooling — it's the
gap between "infrastructure team writes all the code" and "every team manages
their own." The platform pattern bridges this: the infra team builds the
platform, teams consume it through a thin interface, and the platform enforces
the org's standards automatically. You don't need buy-in for compliance if
compliance is the default.

---

## Quick Reference: ADRs by Topic

| Topic | Relevant ADRs |
|-------|---------------|
| Code structure | ADR-001 (multi-cloud Terragrunt), ADR-016 (OpenTofu over Terraform) |
| State management | ADR-002 (AWS state storage), ADR-006 (state bootstrap pattern) |
| IAM / access | ADR-007 (IAM role model), ADR-018 (IRSA for pod identity) |
| Networking | ADR-008 (Cilium CNI), ADR-015 (CIDR allocation), ADR-010 (private EKS), ADR-034 (Transit Gateway), ADR-035 (cross-VPC DNS) |
| Tenant isolation | ADR-027 (hybrid tenant model), ADR-033 (defer vCluster) |
| App deployment | ADR-021 (ArgoCD GitOps), ADR-031 (multi-app), ADR-032 (PR previews) |
| CI/CD | ADR-036 (GitHub OIDC), ADR-038 (platctl CLI) |
| Compliance | ADR-003 (SCP philosophy), ADR-013 (compliance tiers), ADR-014 (Kyverno), ADR-037 (CloudTrail audit logging) |
| Ingress | ADR-017 (Gateway API), ADR-029 (preprod public ingress) |
| Secrets | ADR-019 (External Secrets), ADR-024 (secrets architecture) |
| Container registry | ADR-028 (ECR cross-account), ADR-030 (Route53 subdomain delegation) |

## Verified End-to-End Flows

These have been deployed and validated on live infrastructure:

1. **Tenant onboarding**: add team to `teams.hcl` → `terragrunt apply` →
   namespace + quotas + network policies + ArgoCD app created automatically
2. **App deployment**: push to main → GHA builds image → ECR push via OIDC →
   ArgoCD syncs to preprod → live at `https://demo.preprod.aws.refplat.org`
3. **PR previews**: open PR → GHA builds image → ApplicationSet detects PR →
   kustomize overrides → preview at `https://demo-pr-N.preprod.aws.refplat.org`
   → close PR → auto-cleanup
4. **Tenant isolation**: cross-namespace traffic blocked (verified via probe
   pods), egress allowed, gateway ingress allowed through Cilium identity-based
   policies
5. **Multi-account**: management (governance), platform (shared services),
   preprod (workloads) — cross-account via IAM role assumption, TGW for
   network connectivity, Route53 subdomain delegation for DNS
