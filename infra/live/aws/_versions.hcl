locals {
  source_base = "${get_repo_root()}/infra/modules"

  module_source = {
    naming          = "${local.source_base}/aws//naming"
    networking      = "${local.source_base}/aws//networking"
    organizations   = "${local.source_base}/aws//organizations"
    state_bootstrap = "${local.source_base}/aws//state_bootstrap"
  }

  helm_versions = {}
}
