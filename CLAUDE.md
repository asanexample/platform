# Platform

## Project Overview

Multi-cloud IaC platform using OpenTofu (v1.11) + Terragrunt (v1.x). Currently targets AWS only (Azure/GCP removed).

- **Shared modules** (`infra/modules/`): argocd, argocd-apps, argocd-clusters, cert-manager, cilium, cloudflare/dns_delegation, cluster-rbac, crossplane, external-dns, external-secrets, gateway-config, policy, secret-stores, tailscale, tailscale-admin, tenant-claims, vcluster
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
networking ─┘                        |
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
              crossplane ────────────┤ (eks, nodes, policy) — federated tenant control plane (ADR-046/048); after policy (needs the crossplane-system Kyverno exclusion)
              tenant-claims ─────────┤ (crossplane) — applies the XTenant claims; the Composition provisions each tenant (ADR-046/048)
              cloudnative-pg ────────┤ (eks, nodes) — CNPG operator for the Backstage DB (ADR-051)
              keycloak ──────────────┤ (eks, nodes, ext-secrets, secret-stores, cnpg, gateway) — app-facing OIDC IdP, CNPG-backed (ADR-053, B1); self-owns its HTTPRoute on the shared Gateway (ADR-059) so its endpoint is up before keycloak-config
              keycloak-config ───────┤ (keycloak, eks) — realm + seeded realm users (Keycloak is the IdP of record by default; optional upstream federation, ADR-053/059) + OIDC clients (argocd, backstage) + team group/role taxonomy via the keycloak TF provider (B2); configures Keycloak over an in-cluster kubectl port-forward (scripts/kc-portforward.sh, ADR-059) so deploy needs cluster API access, NOT Tailscale; apply needs keycloak serving (helm_wait)

              backstage ─────────────┘ (eks, nodes, cnpg, ext-secrets, secret-stores, keycloak-config) — developer portal (ADR-051); signs in DIRECTLY against Keycloak (OIDC; the `backstage` client). Dex + oauth2-proxy retired — Keycloak OIDC issues refresh tokens, killing the #202 logout-on-refresh reason for the proxy

tailscale-admin ─── (no cluster deps, manages tailnet ACLs/OAuth)
cloudtrail ──────── (no deps, secrets audit logging)
cloudflare-dns ──── (no deps)
```

Preprod is similar but adds the federated `crossplane` + `tenant-claims` units (the Tenant control plane, ADR-048 — alpha/bravo are provisioned by `Tenant` claims, not the retired `tenants`/`pod-identity` units) and `transit-gateway` as spoke.

Cross-environment units (on platform cluster): route53-delegation, ecr, github-oidc, argocd-apps.

EKS uses BYOCNI (`bootstrap_self_managed_addons = false`), so Cilium must be deployed before node groups join. EKS managed add-ons (coredns) are in a separate `eks-addons` unit since addon pods need the CNI to schedule.

### Apply / Destroy

Full from-scratch teardown + rebuild via `platctl`: `docs/runbooks/platform-rebuild-from-scratch.md` (note:
`platctl` is built to `./bin/platctl` via `make build-platctl` — it is not on PATH by default).

```bash
# Apply (from any env's unit directory, e.g. infra/live/aws/platform/us-east-1/platform/)
terragrunt run --all apply

# Destroy (reverse DAG)
terragrunt run --all destroy --filter-allow-destroy -- -auto-approve

# If EKS API is private-only, enable public endpoint first:
aws eks update-cluster-config --name platform-use1-eks --region us-east-1 \
  --resources-vpc-config endpointPublicAccess=true --profile platform
```

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
| **DeveloperAccess-\<team\>** | PreProd | Per-team, namespace-scoped kubectl (one role per team, provisioned by the Crossplane Tenant Composition + an EKS access entry → `team-<team>:developers`; group-mapped RBAC — see ADR-039) |
| **TerraformStateAccess** | Management | S3 state bucket + DynamoDB lock table |
| **OrganizationAccountAccessRole** | All accounts | Break-glass only |

- Terragrunt providers assume **PlatformDeployer** (via root.hcl)
- Helm/K8s exec auth uses **PlatformDeployer** (via `include.base.locals.deployer_role_arn`)
- kubectl uses **PlatformAdmin** (`aws eks update-kubeconfig --role-arn ...PlatformAdmin`)
- State backend uses **TerraformStateAccess** (via root.hcl remote_state `role_arn`)

## Architecture Decisions

- **Cilium as CNI** (1.19.4) — BYOCNI on EKS, `kubeProxyReplacement = true`. Shared module uses `cloud_provider` variable.
- **Cilium Gateway API** — external Envoy uses reserved `ingress` identity (8), not `host`. Tenant CiliumNetworkPolicies must allow `fromEntities: ["ingress"]`. TLS secrets copied to `cilium-secrets` namespace.
- **SSM Session Manager** for private cluster access (no VPN needed).
- **Hubble TLS** uses `helm` method on AWS to avoid BYOCNI chicken-and-egg with post-install hooks.
- **Node groups separated** from EKS module to enforce Cilium-first ordering.
- **EKS add-ons separated** — coredns can't schedule until CNI + nodes are ready.
- **ArgoCD SSO** — Dex + SAML bridge to AWS Identity Center. SAML app created manually. Module is cloud-agnostic; SSO config injected via `argocd_cm_extra`.
- **Transit Gateway** — hub in platform account, shared to spokes via RAM. Dedicated /28 transit subnets per AZ.
- **Cross-VPC DNS** — two modes via `dns_method`: custom PHZ (cheap, manual IP updates) or Route53 Resolver endpoints (robust, ~$365/mo). EKS-managed PHZs are inaccessible, so we maintain our own.
- **Tailscale Operator** — subnet router advertising VPC CIDR to tailnet. Split DNS managed by `tailscale` K8s unit. OAuth from Secrets Manager.
- **Internal Gateway NLB** — `internal` scheme, services only reachable through Tailscale. TLS via Let's Encrypt DNS-01.
- **Multi-app tenant model** — team identity (isolation) decoupled from app identity (deployment). ECR: `team-<team>/<app>`. Namespace isolation only; vCluster deferred (ADR-033). Tenants are provisioned by the **Crossplane `Tenant` Composition** via an `XTenant` claim (the `tenant-claims` unit) — the sole provisioner since BACK stack P3 (#174); the old `tenant` module + `tenants`/`pod-identity`/`s3-shared` units are retired. `teams.hcl` now only feeds app delivery (`argocd-apps`) + the platform-owned supply-chain policies (`policy` unit); migrated teams carry `migrated = true`. See `docs/architecture/crossplane-tenant-api.md`.
- **PR preview environments** — ArgoCD ApplicationSet PR generator. Apps with `preview = true` get ephemeral deployments. Kustomize patches rewrite HTTPRoute hostnames.
- **Kyverno policy engine** (3.8.1 / app v1.18.1, ADR-014) — `policy` module deploys the HA engine + a bundled local `policies-chart` of ClusterPolicies, layered above the PSA `baseline` floor. Per-tenant image-registry scoping + cross-team IRSA-annotation backstop (tenant AWS access is Pod Identity, ADR-041) + RBAC hardening. **Audit-first** (`validation_failure_action`) then flip to Enforce. No team data in the module (per-tenant map from `teams.hcl` at the unit). **Supply-chain split (ADR-046)**: per-team `restrict-images`/`restrict-route-hostnames` are owned by the Crossplane Tenant Composition (the unit's `migrated_teams` input makes the `policy` module skip them); the platform-owned cosign/SLSA `verify-images`/`verify-attestations` stay here for all teams. Phased rollout (Phases 2–5: mutate/generate, cosign verifyImages, CLI shift-left, reporting/cleanup).

## Authoring Policy-Compliant Workloads (Kyverno)

Kyverno is in **Enforce** mode on **preprod and platform** — non-compliant resources in tenant
namespaces (those labeled `platform.refplat.org/tenant`, e.g. `team-*`) are **rejected at admission**.
Full per-cluster list: `docs/architecture/kyverno-policy-catalog.md`. When writing tenant manifests
(app repos' `k8s/`, or anything applied to a `team-*` namespace):

**Auto-injected by `mutate` — do NOT bother setting (Kyverno adds them when absent):**

- Container `securityContext`: `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, `seccompProfile.type: RuntimeDefault`
- Pod `automountServiceAccountToken: false`
- The `team` label (derived from the namespace name)

**Required — omitting these gets the resource REJECTED:**

- **Image** from the platform ECR **scoped to the team**: `<platform-acct>.dkr.ecr.us-east-1.amazonaws.com/team-<team>/<app>:<tag>` (cross-team images are denied)
- An **explicit, immutable image tag** — never `:latest`, never untagged
- **Resource requests AND limits** (cpu + memory) on every container
- **`livenessProbe` and `readinessProbe`** on every container
- Services must be **`ClusterIP`** — `LoadBalancer`/`NodePort` are denied (ingress is via the shared Gateway / `HTTPRoute`)
- **HTTPRoute/GRPCRoute/TLSRoute hostnames** must be in the team's allow-list (the `Tenant` claim's `hostnames`) — claiming another team's or a platform hostname (or omitting hostnames) is denied (ADR-029)
- Workloads only in `team-*` namespaces — **never `default`**
- **Do not** set `securityContext.allowPrivilegeEscalation: true` or `seccompProfile.type: Unconfined` (backstop policies deny them)
- Tenant AWS access is via **platform-managed EKS Pod Identity** (association → named ServiceAccount; ADR-041/047): use a **named** ServiceAccount (never `default`) and set `serviceAccountName`; declare the access in the `Tenant` claim (`aws.serviceAccount` + `aws.policyStatements`), not `teams.hcl`. ServiceAccounts must **not** carry an `eks.amazonaws.com/role-arn` annotation — IRSA is platform-only; a tenant annotation is denied (backstop `disallow-irsa-annotation-cross-team`)
- **Images must be cosign-signed** (keyless; Enforce on preprod). App CI is a **thin caller** of the shared, app-team-unwritable `asanexample/trusted-ci/build-sign.yml` reusable workflow (build → push → sign → SBOM) + `slsa-provenance.yml` (provenance) — the supply-chain backbone is NOT copied per app (ADR-050; `app-bravo` is the generic starter). Kyverno's `verify-images-team-<team>` admits images signed by the shared `build-sign.yml` identity **gated to the team** by the cert's `githubWorkflowRepository` extension (= the app repo); a per-team app-signed identity (`app-<team>`'s `deploy.yml`/`preview.yml`) is also accepted as a fallback for bespoke-build apps. Another team's image is rejected. Full explainer: `docs/architecture/cosign-image-signing.md`, `docs/runbooks/app-supply-chain-onboarding.md`.
- **No** `cluster-admin` (Cluster)RoleBindings or wildcard (`*`) verbs/resources in Roles

**Recommended (not enforced):** `app.kubernetes.io/name` (can't be auto-derived).

**Regulated tiers only** (`compliance_tier` = hipaa/pci — not the current `standard` clusters):
`runAsNonRoot: true` and `readOnlyRootFilesystem: true` become required.

If a workload legitimately needs to violate a policy, that's a platform decision — see
`docs/runbooks/kyverno-break-glass.md`; don't weaken a policy to fit one app. A minimal compliant
Deployment lives at `app-alpha/k8s/preprod/deployment.yaml`.
