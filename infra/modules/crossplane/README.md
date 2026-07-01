# Crossplane

Installs [Crossplane](https://crossplane.io) **v2** as the environment control plane, **federated per workload
cluster** ([ADR-048](../../../docs/adrs/048-federated-per-cluster-crossplane.md)) — each cluster runs its own
Crossplane and provisions its own environments locally. Part of the BACK stack
([ADR-046](../../../docs/adrs/046-back-stack-for-developer-self-service.md)).

Roles, selected by inputs:

- **Platform (hub) cluster** — Upbound AWS provider family (Pod Identity) for shared AWS provisioning (P1:
  ECR repositories). The hub **also** hosts the **Agent control plane** (`enable_agent_api`, ADR-082): the
  `XAgent` XRD + Composition (`charts/agent-api`) plus its admission policies (`charts/agent-policies`,
  `restrict-agent-envelope` / `restrict-agent-control-plane`) — provisioning **platform agents** (hub-local
  platform infra), which is independent of, and never co-enabled with, the tenant `enable_environment_api`.
- **Workload clusters (preprod/prod)** — `provider-kubernetes` (in-cluster) + the Upbound AWS provider
  family (`ecr`/`iam`/`eks`, Pod Identity) + Composition Functions + the **`XEnvironment` XRD/Composition**
  (`charts/environment-api`). A single `XEnvironment` provisions a **complete** environment: the Kubernetes side
  (namespace, ResourceQuota/LimitRange, NetworkPolicies, CiliumNetworkPolicies, developer RoleBinding,
  per-team Kyverno `restrict-images`/`restrict-route-hostnames`) **and** the AWS side (`Pod-team-<team>` IAM
  role + EKS Pod Identity association, cross-account ECR repo). *(The `DeveloperAccess-<team>` IAM role + EKS
  access entry are part of the design but **not yet emitted** by the v3 Composition — a regression tracked in
  [#647]; the IAM scoping for it already exists on the provisioning role.)* This is the **sole** environment
  provisioner — the old `infra/modules/tenant` module and the
  `environments`/`pod-identity`/`s3-shared` Terragrunt units are **retired** (BACK stack P3, #174).

Claims are delivered by the `argocd-apps` registry-sync of `gitops/environments/` (one Application per `XEnvironment`
claim), **not** a Terragrunt unit — the old `tenant-claims` unit is retired.
The cosign/SLSA supply-chain policies (`verify-images`/`verify-attestations`) are **not** in the claim — they
stay platform-owned in the `policy` module (applied to all products, derived from the Product registry
via the module's `verify_subjects_product` input).

The two Kyverno policies that govern the environment **control plane** itself — `restrict-environment-envelope`
([ADR-049](../../../docs/adrs/049-tenant-model-team-tenant-zone.md)) and `restrict-environment-control-plane` (ADR-046/048) — **do**
live here (`charts/environment-policies`, a `helm_release` gated on `enable_environment_api`, installed after the Team
projection). They match Crossplane CRDs (`XEnvironment`, the projected `Team`, the provider `ProviderConfig`s), so
they must install *after* those CRDs exist. They were deliberately moved out of the `policy` module, which
deploys *before* Crossplane (to pre-create the `crossplane-system` exclusion) — shipping them there made Kyverno
churn its webhook config on the not-yet-existing kinds and stalled the policy install. Tests:
`.kyverno-tests/run.sh` (run by the same CI job as the policy module's). Foundational/platform infra stays on Terragrunt. See
[`docs/architecture/crossplane-environment-api.md`](../../../docs/architecture/crossplane-environment-api.md) for the
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

**Workload cluster (preprod) — the Environment API:**

```hcl
module "crossplane" {
  source             = "../../modules/crossplane"
  cluster_name       = "preprod-use1-eks"
  region             = "us-east-1"
  account_id         = "<preprod-account-id>"
  helm_chart_version = "2.3.1"

  provider_services               = ["ecr", "iam", "eks"] # AWS footprint of a environment
  enable_kubernetes_provider      = true
  kubernetes_provider_hostnetwork = true # Object CRD is multi-version → conversion webhook must be reachable
  functions = [
    { name = "function-go-templating", package = "xpkg.upbound.io/crossplane-contrib/function-go-templating:v0.12.1" },
    { name = "function-auto-ready", package = "xpkg.upbound.io/crossplane-contrib/function-auto-ready:v0.6.5" },
    { name = "function-environment-configs", package = "xpkg.upbound.io/crossplane-contrib/function-environment-configs:v0.7.1" },
  ]
  enable_environment_api          = true
  enable_environment_provisioning = true # scoped provisioning IAM + deny-escalation boundary
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

# Workload clusters (enable_environment_api):
helm_release.crossplane_environment_api       XEnvironment XRD + Composition (charts/environment-api)
helm_release.crossplane_environment_policies  control-plane Kyverno policies (charts/environment-policies)

# Hub only (enable_agent_api, ADR-082):
helm_release.crossplane_agent_api             XAgent XRD + Composition (charts/agent-api)
helm_release.crossplane_agent_policies        XAgent admission policies (charts/agent-policies)

aws_iam_role.provisioner         scoped to ECR repository/team-*  ──┐
aws_eks_pod_identity_association (crossplane-system, provider-aws) ─┘  credentials the provider pods
```

The module creates up to **seven** Helm releases — the three core releases above are always present, plus
the two `environment-*` releases on workload clusters (`enable_environment_api`) and the two `agent-*`
releases on the hub (`enable_agent_api`). Why split the core three: the `aws.upbound.io` ProviderConfig CRD
is installed by the provider **package** (asynchronously), not the core chart. Splitting runtime (the
providers plus a Healthy-gate Job) from config (ProviderConfig) lets the gate guarantee the CRD exists
before the ProviderConfig is applied — avoiding the `kubernetes_manifest` CRD-at-plan-time problem (same rationale as
the `policy` module's local chart). The `*-api`/`*-policies` releases are likewise local charts that install
their XRDs before the policies that match them.

## Acceptance / smoke test

`examples/smoke-ecr-repository.yaml` provisions a `team-xptest/smoke` ECR repo from a managed resource and is
used to demonstrate reconciliation + drift correction (issue #172). It is **not** managed by Terraform —
apply and tear it down by hand.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | ~> 3.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6.0 |
| <a name="provider_helm"></a> [helm](#provider\_helm) | ~> 3.0 |
| <a name="provider_null"></a> [null](#provider\_null) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_eks_pod_identity_association.provisioner](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_pod_identity_association) | resource |
| [aws_iam_policy.environment_boundary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.provisioner](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.provisioner](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [helm_release.crossplane](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.crossplane_agent_api](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.crossplane_agent_policies](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.crossplane_config](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.crossplane_environment_api](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.crossplane_environment_policies](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.crossplane_governance_registry](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.crossplane_runtime](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [null_resource.crd_finalizer_cleanup](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [null_resource.environment_ecr_orphan_sweep](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [null_resource.environment_iam_orphan_sweep](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [aws_iam_policy_document.assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.environment_boundary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.provisioner](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_account_id"></a> [account\_id](#input\_account\_id) | Platform AWS account ID that hosts the environment ECR repositories the provisioning role manages. | `string` | n/a | yes |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | EKS cluster name the Crossplane provider runs on (target of the Pod Identity association). | `string` | n/a | yes |
| <a name="input_helm_chart_version"></a> [helm\_chart\_version](#input\_helm\_chart\_version) | Crossplane Helm chart version (must be v2.x — this module targets the Crossplane v2 API model). | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | AWS region (used to scope the ECR repository ARNs the provisioning role may manage). | `string` | n/a | yes |
| <a name="input_agent_policy_values"></a> [agent\_policy\_values](#input\_agent\_policy\_values) | Overrides for the agent-policies Kyverno chart (restrict-agent-envelope + restrict-agent-control-plane), merged over its values.yaml. Keys: validationFailureAction, envelopeFailureAction, enableAgentEnvelope, failurePolicy, excludePrincipals, iamSensitiveServices, commonLabels. Default {} keeps the chart defaults (Enforce). Only applied when enable\_agent\_api. | `any` | `{}` | no |
| <a name="input_base_domain"></a> [base\_domain](#input\_base\_domain) | Per-cluster ingress domain for environment app hostnames (e.g. preprod.aws.refplat.org). The Composition derives each app's allowed route hostnames from it as <app>-<team>.<base\_domain> + the <app>-<team>-pr-* preview wildcard (ADR-060). Empty = derive nothing (only explicit spec.hostnames are allowed). | `string` | `""` | no |
| <a name="input_create"></a> [create](#input\_create) | Whether to create resources in this module. | `bool` | `true` | no |
| <a name="input_create_developer_cluster_role"></a> [create\_developer\_cluster\_role](#input\_create\_developer\_cluster\_role) | Create the shared `environment-developer` ClusterRole the Composition's per-environment RoleBindings bind to. False on clusters where the retired v1 `environment` module owned it (coexistence); true on a fresh v2 build. | `bool` | `false` | no |
| <a name="input_deployer_role_arn"></a> [deployer\_role\_arn](#input\_deployer\_role\_arn) | IAM role ARN to assume for destroy-time CR finalizer cleanup (the PlatformDeployer) | `string` | `""` | no |
| <a name="input_developer_role_name_prefix"></a> [developer\_role\_name\_prefix](#input\_developer\_role\_name\_prefix) | Name prefix for the per-team developer-access IAM roles the Composition provisions (P2c). Also scoped by the provisioning role's iam:* statements alongside environment\_role\_name\_prefix. | `string` | `"DeveloperAccess-"` | no |
| <a name="input_ecr_orphan_sweep_role_arn"></a> [ecr\_orphan\_sweep\_role\_arn](#input\_ecr\_orphan\_sweep\_role\_arn) | ARN of a role in the platform/ECR account to assume on teardown to force-delete orphaned environment ECR repos (team-*) the Composition created — typically the platform PlatformDeployer (assumable by the teardown's profile). Empty disables the sweep. | `string` | `""` | no |
| <a name="input_ecr_provisioner_role_arn"></a> [ecr\_provisioner\_role\_arn](#input\_ecr\_provisioner\_role\_arn) | ARN of the platform-account role the provider assumes (assumeRoleChain) to create environment ECR repositories cross-account. Empty disables the platform-ecr ProviderConfig. | `string` | `""` | no |
| <a name="input_ecr_registry"></a> [ecr\_registry](#input\_ecr\_registry) | Platform-account ECR registry host (<platform-acct>.dkr.ecr.<region>.amazonaws.com). Used by the Composition for per-team image registry policies + ECR repo creation. | `string` | `""` | no |
| <a name="input_enable_agent_api"></a> [enable\_agent\_api](#input\_enable\_agent\_api) | Install the AGENT control plane (ADR-082): the XAgent XRD + Composition (agent-api chart) + the XAgent<br/>admission policies (agent-policies chart). The HUB only — it provisions platform agents (hub-local platform<br/>infra), NOT tenant Environments (so it is independent of, and never co-enabled with, enable\_environment\_api).<br/>Requires enable\_kubernetes\_provider (the Composition creates ns/SA/RBAC), provider\_services ⊇ {iam, eks}<br/>(the Pod-Identity role + association), the Composition functions, and enable\_environment\_provisioning (the<br/>scoped provisioner role + the deny-escalation permissions boundary the agent's role is capped by). | `bool` | `false` | no |
| <a name="input_enable_environment_api"></a> [enable\_environment\_api](#input\_enable\_environment\_api) | Install the Environment XRD + Composition (the federated environment control plane). Workload clusters only. | `bool` | `false` | no |
| <a name="input_enable_environment_provisioning"></a> [enable\_environment\_provisioning](#input\_enable\_environment\_provisioning) | Grant the provider's provisioning role the (scoped) permissions to create environment AWS resources: IAM<br/>Pod-team roles + EKS Pod Identity associations in this (workload) account, and sts:AssumeRole into the<br/>platform account for ECR. Also creates the deny-escalation permissions boundary attached to every<br/>created role. Workload clusters only (preprod/prod), not the platform hub. | `bool` | `false` | no |
| <a name="input_enable_governance_registry"></a> [enable\_governance\_registry](#input\_enable\_governance\_registry) | Install the governance-registry CRDs (WorkforceRole + Person — the role catalog + workforce roster, ADR-089). Enable wherever the platform control plane reads them (the hub today). | `bool` | `false` | no |
| <a name="input_enable_kubernetes_provider"></a> [enable\_kubernetes\_provider](#input\_enable\_kubernetes\_provider) | Install provider-kubernetes (in-cluster InjectedIdentity) so a Composition can create the environment's Kubernetes resources locally. Enabled on workload clusters (preprod/prod), not the platform hub. | `bool` | `false` | no |
| <a name="input_environment_policy_values"></a> [environment\_policy\_values](#input\_environment\_policy\_values) | Overrides for the environment control-plane Kyverno policies chart (restrict-environment-envelope + restrict-environment-control-plane), merged over its values.yaml. Keys: validationFailureAction (control-plane, default Enforce), envelopeFailureAction (default Audit — set Enforce at the ADR-049 A6 cutover), failurePolicy, excludePrincipals, commonLabels. Default {} keeps the chart defaults, which reproduce what the policy unit passed pre-move. Only applied when enable\_environment\_api. | `any` | `{}` | no |
| <a name="input_environment_pull_account_ids"></a> [environment\_pull\_account\_ids](#input\_environment\_pull\_account\_ids) | AWS account IDs granted cross-account image pull on environment ECR repos (the workload accounts). Mirrors the ecr unit's pull\_account\_ids. | `list(string)` | `[]` | no |
| <a name="input_environment_repo_prefix"></a> [environment\_repo\_prefix](#input\_environment\_repo\_prefix) | ECR repository name prefix the provisioning role may manage. Environment repos are 'team-<team>/<app>', so 'team-' scopes the role to environment repositories only. | `string` | `"team-"` | no |
| <a name="input_environment_resource_prefix"></a> [environment\_resource\_prefix](#input\_environment\_resource\_prefix) | Name prefix for self-service cloud resources the Composition provisions (ADR-073). S3 buckets are named '<prefix><team>-<product>-<stage>-<name>-<hash>'; the provisioner role's S3 actions are scoped to '<prefix>*'. The same prefix is passed to the Composition's EnvironmentConfig so the rendered names always fall inside the role's grant. | `string` | `"refplat-"` | no |
| <a name="input_environment_role_name_prefix"></a> [environment\_role\_name\_prefix](#input\_environment\_role\_name\_prefix) | Name prefix for the IAM roles the provisioning role may create/manage (the environment workload roles). Scopes iam:* on the provisioning role. v2 (Environment API): per-app roles are Pod-<team>-<name>-<env>-<app>, so the prefix is Pod- (the v1 Pod-team-<team> single-role convention is retired); escalation stays capped by the S2 boundary condition, which is name-agnostic. | `string` | `"Pod-"` | no |
| <a name="input_finalizer_clear_script"></a> [finalizer\_clear\_script](#input\_finalizer\_clear\_script) | Non-empty enables the destroy-time teardown cleanup scripts (scripts/*.sh). Only checked for non-emptiness — the scripts themselves are resolved at run time via the checkout's own `git rev-parse --show-toplevel`, not this value, so a worktree's different absolute path can't force a spurious null\_resource replace. Kept as a path-shaped string for unit-wiring compatibility (units still pass get\_repo\_root()). | `string` | `""` | no |
| <a name="input_functions"></a> [functions](#input\_functions) | Crossplane Composition Functions to install, as {name, package}. e.g. function-go-templating. | <pre>list(object({<br/>    name    = string<br/>    package = string<br/>  }))</pre> | `[]` | no |
| <a name="input_helm_repository"></a> [helm\_repository](#input\_helm\_repository) | Crossplane Helm chart repository. | `string` | `"https://charts.crossplane.io/stable"` | no |
| <a name="input_helm_timeout"></a> [helm\_timeout](#input\_helm\_timeout) | Helm release timeout (seconds). Covers provider package download + becoming Healthy. | `number` | `600` | no |
| <a name="input_helm_wait"></a> [helm\_wait](#input\_helm\_wait) | Wait for Helm releases to report ready. Keep true so the provider wait-Job gates ProviderConfig. | `bool` | `true` | no |
| <a name="input_kubernetes_provider_hostnetwork"></a> [kubernetes\_provider\_hostnetwork](#input\_kubernetes\_provider\_hostnetwork) | Run provider-kubernetes on hostNetwork (only if its CRDs expose an apiserver-facing webhook unreachable under the overlay). Default false; flip if a conversion/validation webhook is unreachable. | `bool` | `false` | no |
| <a name="input_kubernetes_provider_package"></a> [kubernetes\_provider\_package](#input\_kubernetes\_provider\_package) | OCI package ref for provider-kubernetes. | `string` | `"xpkg.upbound.io/crossplane-contrib/provider-kubernetes:v1.2.1"` | no |
| <a name="input_management_account_id"></a> [management\_account\_id](#input\_management\_account\_id) | Management (org) AWS account ID. Used by the Composition's DeveloperAccess role trust policy to allow the per-team SSO permission set (Dev-<team>) in both the management and workload accounts to assume the role. Empty disables the SSO trust condition. | `string` | `""` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace Crossplane and its providers run in. | `string` | `"crossplane-system"` | no |
| <a name="input_provider_registry"></a> [provider\_registry](#input\_provider\_registry) | OCI registry + org path the provider packages are pulled from. | `string` | `"xpkg.upbound.io/upbound"` | no |
| <a name="input_provider_service_account"></a> [provider\_service\_account](#input\_provider\_service\_account) | ServiceAccount name the provider pods run as (pinned via DeploymentRuntimeConfig so the Pod Identity association can target it). Environment workloads never use this SA. | `string` | `"provider-aws"` | no |
| <a name="input_provider_services"></a> [provider\_services](#input\_provider\_services) | AWS provider-family members to install (e.g. "ecr", "iam", "eks"). P1 installs only "ecr" — the<br/>smallest footprint that proves reconciliation + drift correction. Later phases extend this (and the<br/>provisioning IAM policy) as the Environment Composition needs IAM roles / Pod Identity associations. | `list(string)` | `[]` | no |
| <a name="input_provider_version"></a> [provider\_version](#input\_provider\_version) | Version tag for the AWS provider packages (must be v2.x to run the Crossplane v2 API model and support the PodIdentity credential source). | `string` | `"v2.5.0"` | no |
| <a name="input_providerconfig_name"></a> [providerconfig\_name](#input\_providerconfig\_name) | Name of the ProviderConfig managed resources reference. 'default' is used when an MR omits providerConfigRef. | `string` | `"default"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to AWS resources created by this module. | `map(string)` | `{}` | no |
| <a name="input_wait_image"></a> [wait\_image](#input\_wait\_image) | kubectl image for the post-install Job that blocks until providers are Healthy (so the aws.upbound.io ProviderConfig CRD — installed by the provider package, not the core chart — exists before ProviderConfig is applied). | `string` | `"registry.k8s.io/kubectl:v1.35.0"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Namespace Crossplane and its providers run in. |
| <a name="output_provider_service_account"></a> [provider\_service\_account](#output\_provider\_service\_account) | ServiceAccount the provider pods run as (target of the Pod Identity association). |
| <a name="output_providerconfig_name"></a> [providerconfig\_name](#output\_providerconfig\_name) | ProviderConfig name managed resources reference by default. |
| <a name="output_provisioner_role_arn"></a> [provisioner\_role\_arn](#output\_provisioner\_role\_arn) | ARN of the IAM role the AWS provider assumes (via EKS Pod Identity) to provision environment resources. Null when no AWS providers are installed (e.g. a K8s-only workload cluster). |
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
  sole credential grant; the `provider-aws` SA is platform-controlled and never used by environment workloads.
  Requires the `eks-pod-identity-agent` addon (see Dependencies).
- **Least privilege.** On a workload cluster the provisioning role (`enable_environment_provisioning`) is scoped
  to exactly the environment footprint: create/manage `Pod-team-*` and `DeveloperAccess-*` IAM roles (CreateRole
  conditioned on the **deny-escalation permissions boundary**, no boundary-editing verbs), EKS Pod Identity
  associations + access entries on this cluster, and `sts:AssumeRole`+`sts:TagSession` into the platform
  `crossplane-ecr-provisioner` role for cross-account ECR. Environment-tagging needs an org SCP `exempt_roles`
  entry (`crossplane-provisioner-*`) since `DenyTeamTagTampering` blocks `Team`-key tagging otherwise. On the
  hub cluster the role is ECR-only (the P1 demo avoids the `Team` tag for that reason).
- **Blast radius.** Excluding `crossplane-system` from RBAC hardening concentrates privilege there; keep it
  locked (no environment workloads/RBAC). Environments must only ever submit namespaced XRs, never raw managed
  resources or ProviderConfigs.
- **Provider startup vs association.** Pod Identity creds resolve at request time; if a provider pod starts
  before the association exists it may run uncredentialed — restart the provider Deployment once if so.
- **Destroy.** Managed resources carry finalizers; delete all MRs before destroying the release or namespace
  teardown hangs.
- **v2 API model.** Composite resources are namespaced and the legacy Claim type is deprecated; the
  `Environment` XRD/Composition is authored against v2 (`apiextensions.crossplane.io/v2`, cluster-scoped XR).
