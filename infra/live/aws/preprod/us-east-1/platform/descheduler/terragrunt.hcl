include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.descheduler
}

# Descheduler (ADR-093) — periodically rebalances pods off over-utilized nodes onto under-utilized ones. On
# preprod this is what stops the post-unpark / post-consolidation pile-up where one small node lands ~99% CPU
# (crash-looping its own kubelet + Karpenter) while another sits idle. Depends only on the cluster API.
dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_id                    = "mock-cluster"
    cluster_endpoint              = "https://mock-endpoint"
    cluster_certificate_authority = "bW9jaw=="
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# Order after node groups — which itself follows Cilium (BYOCNI: CNI before nodes) — so the cluster can
# actually schedule the descheduler pod and Cilium can hand it an IP before the helm wait. Ordering-only.
dependency "node_groups" {
  config_path = "../node-groups"

  mock_outputs                            = {}
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

generate "helm_provider" {
  path      = "helm-provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "helm" {
      kubernetes = {
        host                   = "${dependency.eks.outputs.cluster_endpoint}"
        cluster_ca_certificate = base64decode("${dependency.eks.outputs.cluster_certificate_authority}")

        exec = {
          api_version = "client.authentication.k8s.io/v1beta1"
          command     = "aws"
          args        = ["eks", "get-token", "--cluster-name", "${dependency.eks.outputs.cluster_id}", "--region", "${include.base.locals.region}", "--role-arn", "${include.base.locals.deployer_role_arn}"]
        }
      }
    }
  EOF
}

inputs = {
  cluster_name       = dependency.eks.outputs.cluster_id
  create             = true
  helm_chart_version = include.base.locals.helm_versions.descheduler
  helm_wait          = true

  # preprod is small (1-2 t4g.large) and the most imbalance-prone: aggressive WhenEmptyOrUnderutilized
  # consolidation + staggered post-unpark node bring-up. On a near-capacity 2-node cluster the emptier node is
  # still too "full" to qualify as a rebalance target under tight thresholds, so both CPU thresholds are widened
  # well off the module defaults (only cpu — memory/pods are not the constraint here):
  #  - DESTINATION (underutilized) CPU = 78%. LowNodeUtilization only rebalances if some node is below ALL
  #    thresholds. 2026-07-02 the cool node sat at 39% (1% under the 40% default) → we raised it to 50%.
  #    2026-07-12 the cool node sat at ~68% while the hot node was at 98% and its falco/alloy-profiles DaemonSet
  #    pods were stuck Pending (Insufficient cpu); 68% is above the 50% underutil line, so NO node qualified as a
  #    target and the descheduler no-op'd ("no node is underutilized, nothing to do here"). 78% lets a ~68% node
  #    receive evicted pods, freeing >210m on the hot node (falco 100m + alloy-profiles 110m) so the pinned
  #    DaemonSet pods can finally schedule (an evicted 100m pod can't land back on the full node, so it moves).
  #  - SOURCE (overutilized) CPU = 85%. Above this 2-node cluster's ~81% balanced steady state (so it does not
  #    churn at balance) yet low enough to shed the ~98% hot node. Keeps a gap over underutilized; requests are
  #    static so there's no fluctuation-driven ping-pong.
  #  - Faster cadence (10 min): churn is cheap on non-prod, and this is where a hot node melts down.
  # NOTE: this only rebalances EXISTING capacity (~350m of slack once balanced). If preprod grows past that, the
  # durable fix is bigger nodes, NOT tighter thresholds.
  schedule                 = "*/10 * * * *"
  underutilized_thresholds = { cpu = 78, memory = 50, pods = 50 }
  overutilized_thresholds  = { cpu = 85, memory = 70, pods = 70 }

  tags = include.base.locals.tags
}
