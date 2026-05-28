locals {
  teams = {
    alpha = {
      mode      = "namespace"
      repo_url  = "https://github.com/centric/app-alpha"
      repo_path = "k8s/preprod"
    }
    bravo = {
      mode      = "vcluster"
      repo_url  = "https://github.com/centric/app-bravo"
      repo_path = "k8s/preprod"
    }
  }

  namespace_teams = { for k, v in local.teams : k => v if v.mode == "namespace" }
  vcluster_teams  = { for k, v in local.teams : k => v if v.mode == "vcluster" }
}
