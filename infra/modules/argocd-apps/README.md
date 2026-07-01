# ArgoCD Apps

Creates the ArgoCD AppProjects, Applications, and ApplicationSets that deliver workloads on the platform cluster (the GitOps hub), driven by the git-native registries (ADR-067/069). For each **Product** it creates a scoped `product-<team>-<product>` AppProject and an ApplicationSet whose git-files generator fans out over the Product's **Release** records (`gitops/releases/<team>/<product>/*.yaml`, ADR-071) — one Application per Environment that has a Release, sourcing the app repo's `k8s/overlays/<stage>` with the deployed digest injected as a kustomize image override. With `platform_repo_url` set it also creates the **registry-sync** apps (Products / Environments / Grants), and with `enable_teams` the Team-CR sync app. When `preview_domain` is set, each Environment's `HTTPRoute` hostname is rewritten to `<product>-<team>-<stage>.<preview_domain>`.

> **Note:** per-PR ephemeral preview environments (ADR-032) — a separate, product-scoped `pullRequest`-generator ApplicationSet (`pr-preview.tf`), gated per-product on `products[*].preview` — code landed, pending a manual GitHub App permission check and live verification. See [Notes](#notes).

## Usage

```hcl
module "argocd_apps" {
  source = "../../modules/argocd-apps"

  cluster_server = "https://EXAMPLE.gr7.us-east-1.eks.amazonaws.com"
  ecr_registry   = "<PLATFORM_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com"

  # The platform GitOps repo: drives the registry-sync apps and per-Product delivery.
  platform_repo_url = "https://github.com/asanexample/platform"

  # Sync git-native Team CRs (Kyverno admission inputs) ahead of Environments.
  enable_teams   = true
  teams_repo_url = "https://github.com/asanexample/platform"

  # Per-Product delivery: one ApplicationSet per product, keyed <team>-<product>.
  # preview/services drive the ADR-032 PR-preview ApplicationSet (pr-preview.tf) — preview gates
  # it per-product, services lists the per-service image overrides to build.
  products = {
    "alpha-shop" = {
      team     = "alpha"
      product  = "shop"
      repo_url = "https://github.com/asanexample/app-alpha"
      preview  = true
      services = ["web"]
    }
  }

  # Optional: rewrite each Environment's HTTPRoute host under this base domain; also the base
  # domain the PR-preview ApplicationSet uses for <product>-<team>-dev-pr-<N>.<preview_domain>.
  preview_domain = "preprod.aws.refplat.org"

  # ADR-032: reuse the GitHub App already used for repo-creds (TD2-02b) for the PR-preview
  # ApplicationSet's pullRequest generator too. Empty disables PR-preview delivery.
  github_app_secret_name = "github-asanexample-app-creds"
}
```

## Examples

### Disabled Module

```hcl
module "argocd_apps" {
  source = "../../modules/argocd-apps"

  create = false
}
```

### Registry-sync + Teams only (no per-Product delivery yet)

```hcl
module "argocd_apps" {
  source = "../../modules/argocd-apps"

  cluster_server    = "https://EXAMPLE.gr7.us-east-1.eks.amazonaws.com"
  platform_repo_url = "https://github.com/asanexample/platform"

  enable_teams   = true
  teams_repo_url = "https://github.com/asanexample/platform"

  # products left empty → registry-sync (Products/Environments/Grants) + Teams run,
  # but no Product delivers yet.
  products = {}
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | ~> 3.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | ~> 3.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_helm"></a> [helm](#provider\_helm) | ~> 3.0 |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | ~> 3.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [helm_release.agent_appset](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.product_appset](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.product_pr_preview](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [kubernetes_manifest.agent_appproject](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_manifest.agent_registry_app](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_manifest.agent_registry_project](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_manifest.governance_app](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_manifest.governance_project](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_manifest.product_appproject](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_manifest.registry_app](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_manifest.registry_project](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_manifest.teams_app](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_manifest.teams_project](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_agents"></a> [agents](#input\_agents) | ADR-082: platform agents keyed by XAgent name. Their WORKLOAD is delivered to the HUB (hub\_cluster\_server) into the Composition-made namespace platform-agent-<name>; their identity/RBAC come from the XAgent Composition (not ArgoCD). product\_key is the gitops/products registry key (<team>-<product>), used to EXCLUDE the agent's Product from the preprod per-Product delivery (it ships to the hub instead). | <pre>map(object({<br/>    team        = string # owning team (platform)<br/>    product     = string # product short name (drives the ECR image team-<team>/<product>-<svc>)<br/>    product_key = string # the gitops/products registry key <team>-<product> (the var.products key to exclude)<br/>    repo_url    = string # the app repo (Product.repo), https URL — the Application source<br/>  }))</pre> | `{}` | no |
| <a name="input_argocd_namespace"></a> [argocd\_namespace](#input\_argocd\_namespace) | Namespace where ArgoCD is installed | `string` | `"argocd"` | no |
| <a name="input_cluster_server"></a> [cluster\_server](#input\_cluster\_server) | API server URL of the target cluster | `string` | `""` | no |
| <a name="input_create"></a> [create](#input\_create) | Whether to create ArgoCD app resources | `bool` | `true` | no |
| <a name="input_ecr_registry"></a> [ecr\_registry](#input\_ecr\_registry) | ECR registry host for the per-Product image (ADR-071). The ApplicationSet injects the Release digest as a kustomize image override whose name must match the app overlay's image — <ecr\_registry>/team-<team>/<product>-<service>. | `string` | `""` | no |
| <a name="input_enable_people"></a> [enable\_people](#input\_enable\_people) | Create the platform-people Application that syncs the git-native Person roster (gitops/people) onto the hub (ADR-089). | `bool` | `false` | no |
| <a name="input_enable_roles"></a> [enable\_roles](#input\_enable\_roles) | Create the platform-roles Application that syncs the git-native WorkforceRole catalog (gitops/roles) onto the hub (ADR-089). | `bool` | `false` | no |
| <a name="input_enable_teams"></a> [enable\_teams](#input\_enable\_teams) | Create the platform-teams AppProject + Application that syncs git-native Team CRs to the target cluster (replaces the crossplane-teams Helm projection, ADR-063). | `bool` | `false` | no |
| <a name="input_github_app_secret_name"></a> [github\_app\_secret\_name](#input\_github\_app\_secret\_name) | ADR-032: name of the existing GitHub App repo-creds Secret (in argocd\_namespace) the PR-preview ApplicationSet's pullRequest.github generator authenticates with via appSecretName. Reuses the same App already used for repo-creds (TD2-02b, github-asanexample-app-creds) — its githubAppID/githubAppInstallationID/githubAppPrivateKey keys are exactly what appSecretName expects. Empty disables PR-preview delivery even if products have preview=true. | `string` | `""` | no |
| <a name="input_governance_repo_branch"></a> [governance\_repo\_branch](#input\_governance\_repo\_branch) | Branch/revision for the governance-registry records. | `string` | `"main"` | no |
| <a name="input_governance_repo_url"></a> [governance\_repo\_url](#input\_governance\_repo\_url) | Git repo URL holding the governance-registry record YAMLs (the platform repo). | `string` | `""` | no |
| <a name="input_hub_cluster_server"></a> [hub\_cluster\_server](#input\_hub\_cluster\_server) | ADR-082: the in-cluster (hub) API server the agent control plane + workloads target. ArgoCD's built-in in-cluster (https://kubernetes.default.svc) — the platform cluster ArgoCD itself runs on. The agent control plane lives on the hub (ADR-048-consistent), unlike tenant delivery which targets the preprod workload cluster (cluster\_server). | `string` | `"https://kubernetes.default.svc"` | no |
| <a name="input_platform_repo_branch"></a> [platform\_repo\_branch](#input\_platform\_repo\_branch) | v3: branch of the platform GitOps repo the registry-sync apps + the per-Product ApplicationSet track. | `string` | `"main"` | no |
| <a name="input_platform_repo_url"></a> [platform\_repo\_url](#input\_platform\_repo\_url) | v3: the platform GitOps repo read by the registry-sync apps (gitops/{products,environments,grants}/) and the per-Product delivery ApplicationSet (gitops/releases/<team>/<product>/). Empty disables delivery. | `string` | `""` | no |
| <a name="input_preview_domain"></a> [preview\_domain](#input\_preview\_domain) | Optional base domain. When set: (1) the per-Product delivery ApplicationSet rewrites each Environment's HTTPRoute hostname to <product>-<team>-<stage>.<preview\_domain> (per-stage), and (2) it's also the base domain the ADR-032 PR-preview ApplicationSet (pr-preview.tf) uses for <product>-<team>-dev-pr-<N>.<preview\_domain>. | `string` | `""` | no |
| <a name="input_products"></a> [products](#input\_products) | v3: per-Product delivery, keyed <team>-<product>. One ApplicationSet per product; its git-files generator fans out over the Product's Release records gitops/releases/<team>/<product>/*.yaml → one Application per Environment that has a Release (ADR-071, #377). | <pre>map(object({<br/>    team     = string       # owning team<br/>    product  = string       # product short name (the gitops/{releases,environments}/<team>/<product>/ dir)<br/>    repo_url = string       # the app repo (Product.repo), https URL — the Application source<br/>    preview  = bool         # ADR-032: spec.preview from the product's dev Environment claim — gates the PR-preview ApplicationSet<br/>    services = list(string) # ADR-032: keys(spec.services) from the dev Environment claim — the PR generator's payload carries no service data, so the per-service image override list has to be built from this (Terraform-known) side, not a git-files generator's payload like delivery.tf's does<br/>  }))</pre> | `{}` | no |
| <a name="input_teams_repo_branch"></a> [teams\_repo\_branch](#input\_teams\_repo\_branch) | Branch/revision for the Team CRs repo. | `string` | `"main"` | no |
| <a name="input_teams_repo_path"></a> [teams\_repo\_path](#input\_teams\_repo\_path) | Path within the repo to the Team CR YAMLs (e.g. gitops/teams). | `string` | `"gitops/teams"` | no |
| <a name="input_teams_repo_url"></a> [teams\_repo\_url](#input\_teams\_repo\_url) | Git repo URL holding the Team CR YAMLs (the platform repo). | `string` | `""` | no |

## Outputs

No outputs.
<!-- END_TF_DOCS -->

## Notes

- AppProject whitelists are restrictive by design: ConfigMaps, Secrets, Services, **ServiceAccounts**, Deployments, StatefulSets, **Argo `Rollout`/`AnalysisTemplate`/`AnalysisRun`** (ADR-056 — every workload is a Rollout; Deployment/StatefulSet kept for the migration window), Jobs, CronJobs, HTTPRoutes, and ExternalSecrets.
- `preview_domain` (optional): when set, the per-Product delivery ApplicationSet rewrites each **Environment's** `HTTPRoute` hostname to `<product>-<team>-<stage>.<preview_domain>` — a per-stage host rewrite on the standard delivery, **not** a per-PR ephemeral environment.
- **Per-PR ephemeral preview environments (ADR-032)** — `pr-preview.tf`. A separate `pullRequest`-generator ApplicationSet per product (`products[*].preview == true`), distinct from the Release-keyed delivery ApplicationSet above — deploys into the existing `dev` namespace with `pr-<N>-` kustomize isolation, sourcing the PR's own head-SHA-tagged signed image (no Release record, previews bypass promotion). Reuses the GitHub App already used for repo-creds (`github_app_secret_name`) rather than a separate token. Code landed; pending a manual GitHub App permission grant (Pull requests: Read-only) and live verification.
- `enable_teams` adds a `platform-teams` AppProject + `teams` Application that syncs the git-native `Team` CRs (`teams_repo_path`, e.g. `gitops/teams`) to the target cluster — replacing the `crossplane-teams` Helm projection (ADR-063). The Team CRs are Kyverno admission inputs (envelope / team-must-exist), so the app carries a `sync-wave: "-1"` ahead of the environments registry-sync app; selfHeal converges a claim transiently rejected before its Team lands.
- Setting `platform_repo_url` enables the **registry-sync** apps (ADR-069 §1): per registry kind, a `platform-<kind>` AppProject + an Application that projects the git-native registries onto the cluster as CRs — `products` (`gitops/products`, `Product` CRs, wave `-2`), `environments` (`gitops/environments`, the cluster-scoped `XEnvironment` claims, wave `0`), and `grants` (`gitops/grants`, `AccessGrant` CRs). The `XEnvironment` claims are thus delivered by the `environments` Application under the `platform-environments` AppProject — the retired `enable_tenant_claims`/`platform-tenants`/`tenant-claims-<env>`/`XTenant`/`tenant_claims_repo_path` wiring is replaced by this.
- Per-Product **delivery** (`products` variable, gated on `platform_repo_url`): one `product-<team>-<product>` AppProject + ApplicationSet whose git-files generator fans out over the product's Release records to one Application per Environment.
- **Agent delivery (ADR-082)** (`agents` variable, the `agents.tf` road): the platform-agent control plane delivers to the **hub** (`hub_cluster_server` = ArgoCD's in-cluster `https://kubernetes.default.svc`), unlike tenant delivery which targets the preprod workload cluster. Two pieces — an `agents` **registry-sync** app (a `platform-agents` AppProject whose `clusterResourceWhitelist` is just the `platform.refplat.org/XAgent` kind, projecting `gitops/agents/` onto the hub) and a per-agent **workload** ApplicationSet that fans out over `var.agents` into each Composition-made `platform-agent-<name>` namespace. The agent workload AppProject is deliberately tight: `clusterResourceWhitelist = []` and **no `ServiceAccount`** in the namespace whitelist (the XAgent Composition owns the SA/identity/RBAC — the app must drop its own SA manifest). An agent's `product_key` excludes its Product from the preprod per-Product delivery so it ships only to the hub.

## Related ADRs

- ADR-067: Team→Product→Service→Environment Model
- ADR-082: Platform Agent Runtime
- ADR-032: PR Preview Environments
- ADR-063: Git-Native Team Object
