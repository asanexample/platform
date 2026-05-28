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
    # bravo = {
    #   mode = "vcluster"
    #   apps = {
    #     demo = {
    #       repo_url  = "https://github.com/gangster/app-bravo"
    #       repo_path = "k8s/preprod"
    #       preview   = true
    #     }
    #   }
    # }
  }

  namespace_teams = { for k, v in local.teams : k => v if v.mode == "namespace" }
  vcluster_teams  = { for k, v in local.teams : k => v if v.mode == "vcluster" }
}
