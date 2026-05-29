# Team definitions for the preprod environment.
#
# Each team gets a namespace (team-<name>), resource quotas, network policies,
# and one ArgoCD Application per app entry. Teams with preview-enabled apps
# also get an ApplicationSet for PR preview environments.
#
# Fields:
#   mode      - Isolation mode: "namespace" (default) or "vcluster" (deferred, ADR-033)
#   apps      - Map of app deployments managed by ArgoCD
#     repo_url  - Git repo containing the app's Kubernetes manifests
#     repo_path - Path within the repo to the manifest directory
#     preview   - Whether to create an ApplicationSet for PR preview deployments

locals {
  teams = {
    alpha = {
      mode = "namespace"
      apps = {
        demo = {
          repo_url  = "https://github.com/gangster/app-alpha"
          repo_path = "k8s/preprod"
          preview   = true
        }
      }
    }
    bravo = {
      mode = "namespace"
      apps = {
        demo = {
          repo_url  = "https://github.com/gangster/app-bravo"
          repo_path = "k8s/preprod"
          preview   = false
        }
      }
    }
  }

  namespace_teams = { for k, v in local.teams : k => v if v.mode == "namespace" }
  vcluster_teams  = { for k, v in local.teams : k => v if v.mode == "vcluster" }
}
