# Crossplane

Installs [Crossplane](https://crossplane.io) **v2** as the tenant control plane, **federated per workload
cluster** ([ADR-048](../../../docs/adrs/048-federated-per-cluster-crossplane.md)) — each cluster runs its own
Crossplane and provisions its own tenants locally. Part of the BACK stack
([ADR-046](../../../docs/adrs/046-back-stack-for-developer-self-service.md)).

Two roles, selected by inputs:

- **Platform (hub) cluster** — Upbound AWS provider family (Pod Identity) for shared AWS provisioning (P1:
  ECR repositories).
- **Workload clusters (preprod/prod)** — `provider-kubernetes` (in-cluster) + the Upbound AWS provider
  family (`ecr`/`iam`/`eks`, Pod Identity) + Composition Functions + the **`Tenant` XRD/Composition**
  (`charts/tenant`). A single `Tenant` claim provisions a **complete** tenant: the Kubernetes side
  (namespace, ResourceQuota/LimitRange, NetworkPolicies, CiliumNetworkPolicies, developer RoleBinding,
  per-team Kyverno `restrict-images`/`restrict-route-hostnames`) **and** the AWS side (`Pod-team-<team>` IAM
  role + EKS Pod Identity association, `DeveloperAccess-<team>` IAM role + EKS access entry, cross-account
  ECR repo). This is the **sole** tenant provisioner — the old `infra/modules/tenant` module and the
  `tenants`/`pod-identity`/`s3-shared` Terragrunt units are **retired** (BACK stack P3, #174).

Claims are delivered by the `tenant-claims` Terragrunt unit (see [`infra/modules/tenant-claims`](../tenant-claims/)).
The cosign/SLSA supply-chain policies (`verify-images`/`verify-attestations`) are **not** in the claim — they
stay platform-owned in the `policy` module (applied to all teams, including migrated ones via its
`migrated_teams` input).

The two Kyverno policies that govern the tenant **control plane** itself — `restrict-tenant-envelope`
([ADR-049](../../../docs/adrs/049-tenant-model-team-tenant-zone.md)) and `restrict-tenant-control-plane` (ADR-046/048) — **do**
live here (`charts/tenant-policies`, a `helm_release` gated on `enable_tenant_api`, installed after the Team
projection). They match Crossplane CRDs (`XTenant`, the projected `Team`, the provider `ProviderConfig`s), so
they must install *after* those CRDs exist. They were deliberately moved out of the `policy` module, which
deploys *before* Crossplane (to pre-create the `crossplane-system` exclusion) — shipping them there made Kyverno
churn its webhook config on the not-yet-existing kinds and stalled the policy install. Tests:
`.kyverno-tests/run.sh` (run by the same CI job as the policy module's). Foundational/platform infra stays on Terragrunt. See
[`docs/architecture/crossplane-tenant-api.md`](../../../docs/architecture/crossplane-tenant-api.md) for the
XRD schema, Composition pipeline, and claim lifecycle.

## Usage

**Platform (hub) — AWS provisioning:**

```hcl
module "crossplane" {
  source             = "../../modules/crossplane"
  cluster_name       = "platform-use1-eks"
  region             = "us-east-1"
  account_id         = "<platform-account-id>"
  helm_chart_version = "2.3.1"
  provider_services  = ["ecr"] # Upbound AWS family members
  tags               = local.tags
}
```

**Workload cluster (preprod) — the Tenant API:**

```hcl
module "crossplane" {
  source             = "../../modules/crossplane"
  cluster_name       = "preprod-use1-eks"
  region             = "us-east-1"
  account_id         = "<preprod-account-id>"
  helm_chart_version = "2.3.1"

  provider_services               = ["ecr", "iam", "eks"] # AWS footprint of a tenant
  enable_kubernetes_provider      = true
  kubernetes_provider_hostnetwork = true # Object CRD is multi-version → conversion webhook must be reachable
  functions = [
    { name = "function-go-templating", package = "xpkg.upbound.io/crossplane-contrib/function-go-templating:v0.12.1" },
    { name = "function-auto-ready", package = "xpkg.upbound.io/crossplane-contrib/function-auto-ready:v0.6.5" },
    { name = "function-environment-configs", package = "xpkg.upbound.io/crossplane-contrib/function-environment-configs:v0.7.1" },
  ]
  enable_tenant_api          = true
  enable_tenant_provisioning = true # scoped provisioning IAM + deny-escalation boundary
  ecr_provisioner_role_arn   = "arn:aws:iam::<platform-account-id>:role/crossplane-ecr-provisioner"
  management_account_id      = "<mgmt-account-id>" # DeveloperAccess-<team> SSO trust
  tags                       = local.tags
}
```

### Disabled

```hcl
module "crossplane" {
  source = "../../modules/crossplane"
  create = false
  # cluster_name / region / account_id / helm_chart_version still required by the schema
}
```

## How it fits together

```text
helm_release.crossplane          core (CRDs: Provider, DeploymentRuntimeConfig; package + rbac managers)
        │
helm_release.crossplane_runtime  DeploymentRuntimeConfig (pins SA "provider-aws") + Provider CRs
        │                        + a post-install Job that blocks until providers are Healthy AND the
        │                        aws.upbound.io ProviderConfig CRD is Established
helm_release.crossplane_config   ProviderConfig (credentials.source: PodIdentity)

aws_iam_role.provisioner         scoped to ECR repository/team-*  ──┐
aws_eks_pod_identity_association (crossplane-system, provider-aws) ─┘  credentials the provider pods
```

Why three Helm releases: the `aws.upbound.io` ProviderConfig CRD is installed by the provider **package**
(asynchronously), not the core chart. Splitting runtime (providers + a Healthy-gate Job) from config
(ProviderConfig) lets the gate guarantee the CRD exists before the ProviderConfig is applied — avoiding the
`kubernetes_manifest` CRD-at-plan-time problem (same rationale as the `policy` module's local chart).

## Acceptance / smoke test

`examples/smoke-ecr-repository.yaml` provisions a `team-xptest/smoke` ECR repo from a managed resource and is
used to demonstrate reconciliation + drift correction (issue #172). It is **not** managed by Terraform —
apply and tear it down by hand.

<!-- BEGIN_TF_DOCS -->
<!-- terraform-docs: run `terraform-docs markdown table infra/modules/crossplane` to populate -->
<!-- END_TF_DOCS -->

## Dependencies

- **eks** — the cluster + the EKS Pod Identity agent (the credential path). The platform `eks-addons` unit
  must install the `eks-pod-identity-agent` addon (it serves `169.254.170.23`); platform add-ons otherwise
  use IRSA, so the hub cluster did not have it until Crossplane needed it.
- **node-groups** — providers need nodes to schedule on.
- **policy** — the platform Kyverno unit must exclude `crossplane-system` (principals + namespace) **before**
  this unit applies; Crossplane's rbac-manager authors wildcard provider ClusterRoles at runtime that the
  Enforce `restrict-wildcard-rbac` policy would otherwise deny. See the platform `policy` unit.

## Notes

- **Providers run on `hostNetwork`** (per-provider `DeploymentRuntimeConfig`). The EKS managed control plane
  cannot reach overlay (cluster-pool) pod IPs to invoke a provider's **conversion/validation webhook**
  (`Address is not allowed`) — upjet CRDs like ecr `Repository` are multi-version, so the apiserver must
  reach `/convert`. hostNetwork serves it on the node VPC IP. Each provider gets a unique port triplet
  (`webhookBasePort + i*10` → webhook/metrics/health) to avoid node collisions with Kyverno's hostNetwork
  webhooks (9443/9444) and the node's 8080. Same gotcha as cert-manager/ESO/Kyverno on this cluster.
- **Provider auth is EKS Pod Identity only** (ADR-041): no SA annotation, no OIDC. The association is the
  sole credential grant; the `provider-aws` SA is platform-controlled and never used by tenant workloads.
  Requires the `eks-pod-identity-agent` addon (see Dependencies).
- **Least privilege.** On a workload cluster the provisioning role (`enable_tenant_provisioning`) is scoped
  to exactly the tenant footprint: create/manage `Pod-team-*` and `DeveloperAccess-*` IAM roles (CreateRole
  conditioned on the **deny-escalation permissions boundary**, no boundary-editing verbs), EKS Pod Identity
  associations + access entries on this cluster, and `sts:AssumeRole`+`sts:TagSession` into the platform
  `crossplane-ecr-provisioner` role for cross-account ECR. Tenant-tagging needs an org SCP `exempt_roles`
  entry (`crossplane-provisioner-*`) since `DenyTeamTagTampering` blocks `Team`-key tagging otherwise. On the
  hub cluster the role is ECR-only (the P1 demo avoids the `Team` tag for that reason).
- **Blast radius.** Excluding `crossplane-system` from RBAC hardening concentrates privilege there; keep it
  locked (no tenant workloads/RBAC). Tenants must only ever submit namespaced XRs, never raw managed
  resources or ProviderConfigs.
- **Provider startup vs association.** Pod Identity creds resolve at request time; if a provider pod starts
  before the association exists it may run uncredentialed — restart the provider Deployment once if so.
- **Destroy.** Managed resources carry finalizers; delete all MRs before destroying the release or namespace
  teardown hangs.
- **v2 API model.** Composite resources are namespaced and the legacy Claim type is deprecated; the
  `Tenant` XRD/Composition is authored against v2 (`apiextensions.crossplane.io/v2`, cluster-scoped XR).
