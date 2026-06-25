# ArgoCD Apps

Creates the ArgoCD AppProjects, Applications, and ApplicationSets that deliver workloads on the platform cluster (the GitOps hub), driven by the git-native registries (ADR-067/069). For each **Product** it creates a scoped `product-<team>-<product>` AppProject and an ApplicationSet whose git-files generator fans out over the Product's **Release** records (`gitops/releases/<team>/<product>/*.yaml`, ADR-071) — one Application per Environment that has a Release, sourcing the app repo's `k8s/overlays/<stage>` with the deployed digest injected as a kustomize image override. With `platform_repo_url` set it also creates the **registry-sync** apps (Products / Environments / Grants), and with `enable_teams` the Team-CR sync app. When `preview_domain` is set, each Environment's `HTTPRoute` hostname is rewritten to `<product>-<team>-<stage>.<preview_domain>`.

> **Note:** per-PR ephemeral preview environments (ADR-032) are **not implemented** on this v3 delivery model — the old `tenants` / `github_org` / per-app PR-generator surface was removed at the v3 cutover. See [Notes](#notes).

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
  products = {
    "alpha-shop" = {
      team     = "alpha"
      product  = "shop"
      repo_url = "https://github.com/asanexample/app-alpha"
    }
  }

  # Optional: rewrite each Environment's HTTPRoute host under this base domain.
  preview_domain = "preprod.aws.refplat.org"
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
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | >= 3.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | >= 3.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_helm"></a> [helm](#provider\_helm) | >= 3.0 |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | >= 3.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [helm_release.product_appset](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [kubernetes_manifest.product_appproject](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_manifest.registry_app](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_manifest.registry_project](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_manifest.teams_app](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_manifest.teams_project](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_argocd_namespace"></a> [argocd\_namespace](#input\_argocd\_namespace) | Namespace where ArgoCD is installed | `string` | `"argocd"` | no |
| <a name="input_cluster_server"></a> [cluster\_server](#input\_cluster\_server) | API server URL of the target cluster | `string` | `""` | no |
| <a name="input_create"></a> [create](#input\_create) | Whether to create ArgoCD app resources | `bool` | `true` | no |
| <a name="input_ecr_registry"></a> [ecr\_registry](#input\_ecr\_registry) | ECR registry host for the per-Product image (ADR-071). The ApplicationSet injects the Release digest as a kustomize image override whose name must match the app overlay's image — <ecr\_registry>/team-<team>/<product>-<service>. | `string` | `""` | no |
| <a name="input_enable_teams"></a> [enable\_teams](#input\_enable\_teams) | Create the platform-teams AppProject + Application that syncs git-native Team CRs to the target cluster (replaces the crossplane-teams Helm projection, ADR-063). | `bool` | `false` | no |
| <a name="input_platform_repo_branch"></a> [platform\_repo\_branch](#input\_platform\_repo\_branch) | v3: branch of the platform GitOps repo the registry-sync apps + the per-Product ApplicationSet track. | `string` | `"main"` | no |
| <a name="input_platform_repo_url"></a> [platform\_repo\_url](#input\_platform\_repo\_url) | v3: the platform GitOps repo read by the registry-sync apps (gitops/{products,environments,grants}/) and the per-Product delivery ApplicationSet (gitops/releases/<team>/<product>/). Empty disables delivery. | `string` | `""` | no |
| <a name="input_preview_domain"></a> [preview\_domain](#input\_preview\_domain) | Optional base domain. When set, the per-Product delivery ApplicationSet rewrites each Environment's HTTPRoute hostname to <product>-<team>-<stage>.<preview\_domain> (a per-stage host rewrite — NOT per-PR previews; those, ADR-032, are not yet implemented on the v3 model). | `string` | `""` | no |
| <a name="input_products"></a> [products](#input\_products) | v3: per-Product delivery, keyed <team>-<product>. One ApplicationSet per product; its git-files generator fans out over the Product's Release records gitops/releases/<team>/<product>/*.yaml → one Application per Environment that has a Release (ADR-071, #377). | <pre>map(object({<br/>    team     = string # owning team<br/>    product  = string # product short name (the gitops/{releases,environments}/<team>/<product>/ dir)<br/>    repo_url = string # the app repo (Product.repo), https URL — the Application source<br/>  }))</pre> | `{}` | no |
| <a name="input_teams_repo_branch"></a> [teams\_repo\_branch](#input\_teams\_repo\_branch) | Branch/revision for the Team CRs repo. | `string` | `"main"` | no |
| <a name="input_teams_repo_path"></a> [teams\_repo\_path](#input\_teams\_repo\_path) | Path within the repo to the Team CR YAMLs (e.g. gitops/teams). | `string` | `"gitops/teams"` | no |
| <a name="input_teams_repo_url"></a> [teams\_repo\_url](#input\_teams\_repo\_url) | Git repo URL holding the Team CR YAMLs (the platform repo). | `string` | `""` | no |

## Outputs

No outputs.
<!-- END_TF_DOCS -->

## Notes

- AppProject whitelists are restrictive by design: Deployments, StatefulSets, Services, ConfigMaps, Secrets, Jobs, CronJobs, HTTPRoutes, and ExternalSecrets.
- `preview_domain` (optional): when set, the per-Product delivery ApplicationSet rewrites each **Environment's** `HTTPRoute` hostname to `<product>-<team>-<stage>.<preview_domain>` — a per-stage host rewrite on the standard delivery, **not** a per-PR ephemeral environment.
- **Per-PR ephemeral preview environments (ADR-032) are NOT implemented** on the v3 delivery model. The v2 surface that drove them (`tenants`, `github_org`, `preview_appset`, `github_token_secret_name`, the `preview = true` per-app flag in `teams.hcl`) was removed at the v3 cutover (ADR-067/069). Re-implementing previews on the Release-keyed model — a GitHub `pullRequest` generator with `pr-<N>-` isolation + per-PR hostname/image — is future work; ADR-032 remains the intended design.
- `enable_teams` adds a `platform-teams` AppProject + `teams` Application that syncs the git-native `Team` CRs (`teams_repo_path`, e.g. `gitops/teams`) to the target cluster — replacing the `crossplane-teams` Helm projection (ADR-063). The Team CRs are Kyverno admission inputs (envelope / team-must-exist), so the app carries a `sync-wave: "-1"` ahead of the environments registry-sync app; selfHeal converges a claim transiently rejected before its Team lands.
- Setting `platform_repo_url` enables the **registry-sync** apps (ADR-069 §1): per registry kind, a `platform-<kind>` AppProject + an Application that projects the git-native registries onto the cluster as CRs — `products` (`gitops/products`, `Product` CRs, wave `-2`), `environments` (`gitops/environments`, the cluster-scoped `XEnvironment` claims, wave `0`), and `grants` (`gitops/grants`, `AccessGrant` CRs). The `XEnvironment` claims are thus delivered by the `environments` Application under the `platform-environments` AppProject — the retired `enable_tenant_claims`/`platform-tenants`/`tenant-claims-<env>`/`XTenant`/`tenant_claims_repo_path` wiring is replaced by this.
- Per-Product **delivery** (`products` variable, gated on `platform_repo_url`): one `product-<team>-<product>` AppProject + ApplicationSet whose git-files generator fans out over the product's Release records to one Application per Environment.

## Related ADRs

- ADR-067: Team→Product→Service→Environment Model
- ADR-032: PR Preview Environments
- ADR-063: Git-Native Team Object
