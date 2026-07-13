include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.karpenter
}

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_id                    = "mock-cluster"
    cluster_endpoint              = "https://mock-endpoint"
    cluster_certificate_authority = "bW9jaw=="
    cluster_security_group_id     = "sg-mock"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# Karpenter runs on the system node group + reuses its node IAM role; depend on node-groups so both exist.
dependency "node_groups" {
  config_path = "../node-groups"

  mock_outputs = {
    node_role_arn = "arn:aws:iam::000000000000:role/mock-node"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

dependency "networking" {
  config_path = "../networking"

  mock_outputs = {
    subnet_ids = { "az1-kubernetes" = "subnet-mock" }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# Cilium must be on every node before pods schedule (BYOCNI); eks-addons carries the Pod Identity agent the
# controller authenticates through. Order after both.
dependency "cilium" {
  config_path = "../cilium"

  mock_outputs                            = {}
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

dependency "eks_addons" {
  config_path = "../eks-addons"

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
  # Foundational — on by default (enable_karpenter, dev+prod). create=false applies as a no-op.
  create       = include.base.locals.enable_karpenter
  cluster_name = dependency.eks.outputs.cluster_id
  aws_region   = include.base.locals.region

  node_role_arn             = dependency.node_groups.outputs.node_role_arn
  cluster_security_group_id = dependency.eks.outputs.cluster_security_group_id
  subnet_ids                = [for name, id in dependency.networking.outputs.subnet_ids : id if can(regex("kubernetes$", name))]
  single_az                 = include.base.locals.single_az_nodes
  node_arch                 = include.base.locals.node_arch

  # This is the stateful hub (Prometheus/Mimir/Loki/Tempo/Pyroscope, Keycloak, CNPG). WhenEmptyOrUnderutilized
  # lets Karpenter reclaim UNDERUTILIZED nodes (not just fully-empty ones) — needed because the post-unpark
  # scheduling storm over-provisions small on-demand nodes that WhenEmpty then never reclaimed (6 nodes at
  # ~20% CPU observed 2026-07-13). The stateful TSDBs/DBs stay protected: they carry `karpenter.sh/do-not-disrupt`
  # + PDBs, which Karpenter honors under EITHER policy, so consolidation drains only stateless/underutilized
  # capacity and won't disrupt a running stateful pod or violate a PDB. (ADR-078.)
  capacity_types       = ["on-demand"]
  consolidation_policy = "WhenEmptyOrUnderutilized"
  consolidate_after    = "1m"
  cpu_limit            = 32
  memory_limit         = "128Gi"
  # Require 8 GiB+ nodes (t4g.large, like the system group). The observability hub's per-node DaemonSets
  # (Cilium, Beyla, Alloy, node-exporter) eat ~3.2 GiB — a 4 GiB t4g.medium exhausts memory and flaps NotReady.
  min_instance_memory_mib = 6144

  high_availability  = include.base.locals.high_availability
  helm_chart_version = include.base.locals.helm_versions.karpenter
  helm_wait          = true

  tags = include.base.locals.tags
}
