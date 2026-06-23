# Platform

## Project Overview

Multi-cloud IaC platform using OpenTofu (v1.12.1) + Terragrunt (v1.0.7). Currently targets AWS only (Azure/GCP removed). CLI tool versions (tofu, terragrunt, kubectl, helm, awscli) are pinned canonically in `/.tool-versions` — the single source of truth read by local dev (mise/asdf), CI, and the self-hosted runner image.

- **Shared modules** (`infra/modules/`): actions-runner-controller, argocd, argocd-apps, argocd-clusters, cert-manager, cilium, cloudflare/dns_delegation, cluster-rbac, crossplane, external-dns, external-secrets, gateway-config, github-teams, policy, secret-stores, tailscale, tailscale-admin, tenant-claims, vcluster
- **AWS modules** (`infra/modules/aws/`): cloudtrail, cross-vpc-dns, ecr, eks, eks-addons, eks-node-group, github_oidc, iam_roles, identity_center, networking, organizations, route53, route53_delegation, ssm-bastion, state_bootstrap, transit-gateway
- **Live configs**: `infra/live/aws/` -- environment-specific Terragrunt units

## Terragrunt Config Hierarchy

```text
root.hcl              Remote state (S3), providers, terraform_binary
  └─ common.hcl       Cloud-wide defaults, loads secrets.hcl, tags
      └─ env.hcl      Account ID (from secrets), env tags
          └─ region.hcl / network.hcl    Region, CIDRs
              └─ workload.hcl            Workload name, compliance tier
                  └─ terragrunt.hcl      Unit-level inputs and dependencies
```

`_base.hcl` loads all layers and exposes them to units via `include.base.locals.*`. Units include it as:

```hcl
include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}
```

### Secrets

Sensitive values (account IDs, emails, SSO URLs) live in `infra/live/aws/secrets.hcl` (gitignored). See `secrets.hcl.example` for the structure. Loaded via `read_terragrunt_config("${get_repo_root()}/infra/live/aws/secrets.hcl")` in common.hcl, then exposed through `_base.hcl`:

```hcl
include.base.locals.account_ids["platform"]   # AWS account ID
include.base.locals.account_id                 # current env's account ID
include.base.locals.admin_email                # contact email
include.base.locals.account_emails["preprod"]  # per-account email
```

## Deployment Ordering (AWS)

```text
iam-roles ──┐
             ├─> eks -> cilium -> node-groups -> ssm-bastion
networking ─┘                        ├─> karpenter (eks, cilium, node-groups, eks-addons) — node autoscaling (ADR-078); runs on the system group, provisions/consolidates workload nodes. Cilium-first via the node.cilium.io/agent-not-ready startup taint.
                                     |
              route53 ───────────────┤
              eks-addons ────────────┤ (eks, cilium, nodes)
              cert-manager ──────────┤ (eks, nodes, r53)
              external-dns ──────────┤ (eks, nodes, r53)
              external-secrets ──────┤ (eks, nodes)
              secret-stores ─────────┤ (eks, nodes, ext-secrets)
              argocd ────────────────┤ (eks, nodes, keycloak-config) — SSO via Keycloak OIDC + team-scoped RBAC (ADR-053/059, B3); the keycloak-config dep also transitively orders argocd after the ESO/secret-store chain for its OIDC ExternalSecret
              argocd-clusters ──────┤ (argocd, preprod eks+iam-roles)
              tailscale ─────────────┤ (eks, nodes, ext-secrets)
              transit-gateway (hub) ─┤ (networking)
              cross-vpc-dns ─────────┤ (networking, preprod eks)
              gateway ───────────────┤ (eks, cilium, cert-mgr, ext-dns, r53) — foundational shared Gateway + ClusterIssuer (ADR-059); EARLY, no app deps, so ingress is up before keycloak-config
              gateway-config ────────┘ (eks, gateway, argocd) — per-app HTTPRoutes only (argocd/grafana/backstage); the Gateway moved to the `gateway` unit, keycloak self-routes
              cluster-rbac ──────────┤ (eks) — platform-operator ClusterRole (ADR-040)
              policy ────────────────┤ (eks, nodes) — Kyverno engine + ClusterPolicies (ADR-014), before crossplane
              crossplane ────────────┤ (eks, nodes, policy) — federated environment control plane (ADR-046/048/067); applies the `XEnvironment` XRD + Composition (the `environment-api`/`environment-policies` charts); after policy. The `XEnvironment` claims are delivered by argocd-apps (the `gitops/environments` registry-sync), not a Terragrunt unit
              cloudnative-pg ────────┤ (eks, nodes) — CNPG operator for the Backstage DB (ADR-051)
              keycloak ──────────────┤ (eks, nodes, ext-secrets, secret-stores, cnpg, gateway) — app-facing OIDC IdP, CNPG-backed (ADR-053, B1); self-owns its HTTPRoute on the shared Gateway (ADR-059) so its endpoint is up before keycloak-config
              keycloak-config ───────┤ (keycloak, eks) — realm + seeded realm users (Keycloak is the IdP of record by default; optional upstream federation, ADR-053/059) + OIDC clients (argocd, backstage) + team group/role taxonomy via the keycloak TF provider (B2); configures Keycloak over an in-cluster kubectl port-forward (scripts/kc-portforward.sh, ADR-059) so deploy needs cluster API access, NOT Tailscale; apply needs keycloak serving (helm_wait)

              backstage ─────────────┘ (eks, nodes, cnpg, ext-secrets, secret-stores, keycloak-config) — developer portal (ADR-051); signs in DIRECTLY against Keycloak (OIDC; the `backstage` client). Dex + oauth2-proxy retired — Keycloak OIDC issues refresh tokens, killing the #202 logout-on-refresh reason for the proxy

tailscale-admin ─── (no cluster deps, manages tailnet ACLs/OAuth)
cloudtrail ──────── (no deps, secrets audit logging)
cloudflare-dns ──── (no deps)

actions-runner-controller ─ (eks, nodes, ext-secrets, secret-stores; policy must carry the arc-systems/arc-runners excludes first) — self-hosted GitHub Actions runners (ARC) on the platform cluster for in-VPC CI (ADR-065 / #323). **Applied LOCALLY / via platctl (break-glass)** — it's what lets CI manage the cluster, so it can't bootstrap itself. Manual prereq: the GitHub App + its Secrets Manager secret (docs/runbooks/arc-github-app.md).
```

Preprod is similar but adds the federated `crossplane` + `tenant-claims` units (the Environment control plane, ADR-048 — alpha/bravo are provisioned by `Environment` claims, not the retired `environments`/`pod-identity` units) and `transit-gateway` as spoke.

Cross-environment units (on platform cluster): route53-delegation, ecr, github-oidc, argocd-apps, github-teams (org-Team ownership of app repos, registry-derived — ADR-072).

EKS uses BYOCNI (`bootstrap_self_managed_addons = false`), so Cilium must be deployed before node groups join. EKS managed add-ons (coredns) are in a separate `eks-addons` unit since addon pods need the CNI to schedule.

### Apply / Destroy

Full from-scratch teardown + rebuild via `platctl`: `docs/runbooks/platform-rebuild-from-scratch.md` (note:
`platctl` is built to `./bin/platctl` via `make build-platctl` — it is not on PATH by default).

```bash
# Apply (from any env's unit directory, e.g. infra/live/aws/platform/us-east-1/platform/)
terragrunt run --all apply

# Destroy (reverse DAG)
terragrunt run --all destroy --filter-allow-destroy -- -auto-approve
```

The EKS API is **private-only by design** (ADR-010). For routine apply/maintenance, reach it over
**Tailscale** — the `*-eks-subnet-router` advertises the VPC CIDR and split-DNS resolves the private
endpoint to its VPC ENI IPs, so `terragrunt apply`, `kubectl`, etc. work directly once you're on the
tailnet (`tailscale status` should list the subnet routers). **Do NOT enable the public endpoint** for
ordinary operations. The only exception is a full from-scratch teardown/rebuild, where Tailscale itself
is destroyed — `platctl` handles that bootstrap escape (its unlock/lockdown phases toggle the endpoint
and re-disable it automatically; see `docs/runbooks/platform-rebuild-from-scratch.md`).

All dependency blocks have `mock_outputs` so destroy works even if upstream dependencies are already gone.

## Key Commands

```bash
# Plan/apply from any live unit directory
terragrunt plan
terragrunt apply

# Bootstrap/teardown (preferred)
platctl bootstrap
platctl bootstrap --dry-run
platctl teardown

# Validate deployed infrastructure
platctl validate
platctl validate --env platform
platctl validate --check tailscale

# Configure kubectl contexts
platctl kubeconfig

# Format checks
tofu fmt -check -recursive infra/modules/
terragrunt hclfmt --check

# Tests (Terratest, Go)
cd infra/tests/aws/<module> && go test -v -timeout 30m

# Private cluster access
./scripts/eks-tunnel.sh <cluster-name> <region>
```

## Pre-commit Hooks

`.githooks/pre-commit` runs tofu fmt, terragrunt hclfmt, and tofu validate on staged files. Activate with:

```bash
git config core.hooksPath .githooks
```

## Module Code Style

Use section headers to organize `main.tf` in Terraform/OpenTofu modules:

```hcl
# ---------------------------------------------------------------------------
# Section Name
# ---------------------------------------------------------------------------
```

Group related resources under a header (e.g. "IAM", "KMS", "EKS Cluster"). No headers needed in small modules with only a few resources.

## Testing Conventions

- Terratest (Go) for all modules. Tests live in `infra/tests/aws/<module>/`.
- Plan-only tests for modules that cannot be safely apply/destroyed in CI.
- Test fixtures in `infra/tests/aws/<module>/fixtures/`.
- Must use OpenTofu binary: set `TerraformBinary: "tofu"` in test options.

## AWS Accounts

Real account IDs are in `infra/live/aws/secrets.hcl` (gitignored). See `infra/live/aws/secrets.hcl.example` for the structure.

Cross-account access uses purpose-built IAM roles (see IAM Roles below). `OrganizationAccountAccessRole` retained as break-glass only.

The **Test** account (`157263244316`, Terratest sandbox) is a standard `PlatformDeployer`-managed account; an org SCP (`DenyTeamTagTampering`) forbids human SSO admins from tagging IAM, so its IaC runs via `PlatformDeployer` like every other account. Setup, the one-time bootstrap, and the apply procedure: `docs/runbooks/test-sandbox-account.md`.

## IAM Roles

| Role | Account | Purpose |
|------|---------|---------|
| **PlatformAdmin** | Platform, PreProd | kubectl operate/debug + SSM tunnel — least-privilege (read+operate, NOT author; cluster authoring via ArgoCD, AWS via PlatformDeployer, emergencies via break-glass — ADR-040) |
| **PlatformDeployer** | Platform, PreProd | Terragrunt apply, Helm/K8s providers |
| **DeveloperAccess-\<team\>** | PreProd | Per-team, namespace-scoped kubectl (one role per team, provisioned by the Crossplane Environment Composition + an EKS access entry → the team's per-Environment `<team>-<product>-<stage>:developers` groups bound to the `environment-developer` ClusterRole; group-mapped RBAC — see ADR-039) |
| **TerraformStateAccess** | Management | S3 state bucket + DynamoDB lock table |
| **OrganizationAccountAccessRole** | All accounts | Break-glass only |

- Terragrunt providers assume **PlatformDeployer** (via root.hcl)
- Helm/K8s exec auth uses **PlatformDeployer** (via `include.base.locals.deployer_role_arn`)
- kubectl uses **PlatformAdmin** (`aws eks update-kubeconfig --role-arn ...PlatformAdmin`)
- State backend uses **TerraformStateAccess** (via root.hcl remote_state `role_arn`)

## Architecture Decisions

- **Cilium as CNI** (1.19.4) — BYOCNI on EKS, `kubeProxyReplacement = true`. Shared module uses `cloud_provider` variable.
- **Cilium Gateway API** — external Envoy uses reserved `ingress` identity (8), not `host`. Environment CiliumNetworkPolicies must allow `fromEntities: ["ingress"]`. TLS secrets copied to `cilium-secrets` namespace.
- **SSM Session Manager** for private cluster access (no VPN needed).
- **Hubble TLS** uses `helm` method on AWS to avoid BYOCNI chicken-and-egg with post-install hooks.
- **Node groups separated** from EKS module to enforce Cilium-first ordering.
- **EKS add-ons separated** — coredns can't schedule until CNI + nodes are ready.
- **ArgoCD SSO** — Dex + SAML bridge to AWS Identity Center. SAML app created manually. Module is cloud-agnostic; SSO config injected via `argocd_cm_extra`.
- **Transit Gateway** — hub in platform account, shared to spokes via RAM. Dedicated /28 transit subnets per AZ.
- **Cross-VPC DNS** — two modes via `dns_method`: custom PHZ (cheap, manual IP updates) or Route53 Resolver endpoints (robust, ~$365/mo). EKS-managed PHZs are inaccessible, so we maintain our own.
- **Tailscale Operator** — subnet router advertising VPC CIDR to tailnet. Split DNS managed by `tailscale` K8s unit. OAuth from Secrets Manager.
- **Internal Gateway NLB** — `internal` scheme, services only reachable through Tailscale. TLS via Let's Encrypt DNS-01.
- **Team→Product→Service→Environment model (ADR-067)** — ownership (Team) decoupled from the deployment unit (Environment = a Product at a Stage). ECR: `team-<team>/<product>-<svc>`. Namespace isolation only; vCluster deferred (ADR-033). Environments are provisioned by the **Crossplane `Environment` Composition** via an `XEnvironment` claim (`gitops/environments/<team>/<product>/<stage>.yaml`) — the sole provisioner; the old v2 `tenant`/`tenant-claims`/`pod-identity`/`s3-shared` units are retired. **Registries-as-single-source (ADR-061/063/067):** the git-native `Team` CR (`gitops/teams/`), `Product` registry (`gitops/products/<team>/<product>.yaml` — repo, tenancy, domains), and `XEnvironment` claims (`gitops/environments/`) are the source of truth — `argocd-apps`, `policy`, and `github-oidc` derive (`fileset`+`yamldecode`) per-Product from the registry; the app-delivery `teams.hcl` is retired. **Deprovisioning (ADR-062 #283):** `spec.lifecycle.phase: decommissioning` is a reversible suspend (the Composition zeroes the ResourceQuota); the hard-delete (claim removal) is gated decommission-first + admin-reviewed by the gitops Gate, and ECR is retained (`deletionPolicy: Orphan`). See `docs/runbooks/environment-deprovisioning.md`. See `docs/architecture/crossplane-environment-api.md`.
- **PR preview environments** — ArgoCD ApplicationSet PR generator. Apps with `preview = true` get ephemeral deployments. Kustomize patches rewrite HTTPRoute hostnames.
- **Kyverno policy engine** (3.8.1 / app v1.18.1, ADR-014) — `policy` module deploys the HA engine + a bundled local `policies-chart` of ClusterPolicies, layered above the PSA `baseline` floor. Per-product image-registry scoping + cross-team IRSA-annotation backstop (environment AWS access is Pod Identity, ADR-041) + RBAC hardening. **Audit-first** (`validation_failure_action`) then flip to Enforce. No team data in the module (per-product maps derived from the `Product` registry at the unit — `verify_subjects_product`/`attest_caller_repos` from `spec.repo`). **Supply-chain split (ADR-046)**: per-product `restrict-images`/`restrict-route-hostnames` are owned by the Crossplane Environment Composition; the platform-owned cosign/SLSA `verify-images-product`/`verify-attestations-product` stay here for all products. Phased rollout (Phases 2–5: mutate/generate, cosign verifyImages, CLI shift-left, reporting/cleanup).

## Authoring Policy-Compliant Workloads (Kyverno)

Kyverno is in **Enforce** mode on **preprod and platform** — non-compliant resources in environment
namespaces (those labeled `platform.refplat.org/environment`, named `<team>-<name>-<env>`, e.g. `alpha-demo-dev`)
are **rejected at admission**. Full per-cluster list: `docs/architecture/kyverno-policy-catalog.md`. When
writing environment manifests (app repos' `k8s/`, or anything applied to an environment namespace):

**Auto-injected by `mutate` — do NOT bother setting (Kyverno adds them when absent):**

- Container `securityContext`: `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, `seccompProfile.type: RuntimeDefault`
- Pod `automountServiceAccountToken: false`
- The `team` label (derived from the namespace name)

**Required — omitting these gets the resource REJECTED:**

- **Image** from the platform ECR **scoped to the team/product**: `<platform-acct>.dkr.ecr.us-east-1.amazonaws.com/team-<team>/<product>-<svc>:<tag>` (cross-team images are denied)
- An **explicit, immutable image tag** — never `:latest`, never untagged
- **Resource requests AND limits** (cpu + memory) on every container
- **`livenessProbe` and `readinessProbe`** on every container
- Services must be **`ClusterIP`** — `LoadBalancer`/`NodePort` are denied (ingress is via the shared Gateway / `HTTPRoute`)
- **HTTPRoute/GRPCRoute/TLSRoute hostnames** must be in the team's allow-list (the `Environment` claim's `hostnames`) — claiming another team's or a platform hostname (or omitting hostnames) is denied (ADR-029)
- Workloads only in environment namespaces (`<team>-<name>-<env>`, e.g. `alpha-demo-dev`) — **never `default`**
- **Do not** set `securityContext.allowPrivilegeEscalation: true` or `seccompProfile.type: Unconfined` (backstop policies deny them)
- Environment AWS access is via **platform-managed EKS Pod Identity** (association → named ServiceAccount; ADR-041/047): use a **named** ServiceAccount (never `default`) and set `serviceAccountName`; declare the access in the `XEnvironment` claim (`services.<svc>.serviceAccount` + `services.<svc>.permissions.aws.policyStatements`), not `teams.hcl`. `policyStatements` are **deny-set-validated** (ADR-062 §4, #282) at CI + admission (`restrict-environment-envelope/policystatements-no-escalation`): `iam`/`sts`/`organizations`/`account` actions + bare `*` wildcards are denied, and the minted role is boundary-capped at runtime (resource scoping like `s3:*` on `*` is allowed for now). ServiceAccounts must **not** carry an `eks.amazonaws.com/role-arn` annotation — IRSA is platform-only; an environment annotation is denied (backstop `disallow-irsa-annotation-cross-team`)
- **Images must be cosign-signed** (keyless; Enforce on preprod). App CI is a **thin caller** of the shared, app-team-unwritable `asanexample/trusted-ci/build-sign.yml` reusable workflow (build → push → sign → SBOM) + `slsa-provenance.yml` (provenance) — the supply-chain backbone is NOT copied per app (ADR-050; the New Product scaffolder skeleton is the starter). Kyverno's `verify-images-product-<team>-<product>` admits images signed by the shared `build-sign.yml` identity **gated to the product** by the cert's `githubWorkflowRepository` extension (= the app repo `<team>-<product>`); a per-product app-signed identity (the app repo's `deploy.yml`/`preview.yml`) is also accepted as a fallback for bespoke-build apps. Another team's image is rejected. Full explainer: `docs/architecture/cosign-image-signing.md`, `docs/runbooks/app-supply-chain-onboarding.md`.
- **No** `cluster-admin` (Cluster)RoleBindings or wildcard (`*`) verbs/resources in Roles

**Recommended (not enforced):** `app.kubernetes.io/name` (can't be auto-derived).

**Regulated tiers only** (`compliance_tier` = hipaa/pci — not the current `standard` clusters):
`runAsNonRoot: true` and `readOnlyRootFilesystem: true` become required.

If a workload legitimately needs to violate a policy, that's a platform decision — see
`docs/runbooks/kyverno-break-glass.md`; don't weaken a policy to fit one app. A minimal compliant
Deployment lives at `docs/examples/compliant-deployment.yaml` (the New Product scaffolder emits the same
shape automatically).
