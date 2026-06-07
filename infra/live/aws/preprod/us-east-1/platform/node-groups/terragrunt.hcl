include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.eks_node_group
}

dependency "networking" {
  config_path = "../networking"

  mock_outputs = {
    subnet_ids = {}
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_id = "mock-cluster"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

dependency "cilium" {
  config_path = "../cilium"

  mock_outputs                            = {}
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

locals {
  # Graviton (arm64/t4g) vs x86 (t3), driven by include.base.locals.node_arch. (Single-AZ subnet selection
  # is done in the module — terragrunt locals can't read dependency outputs.)
  _arm         = include.base.locals.node_arch == "arm64"
  sys_instance = local._arm ? "t4g.large" : "t3.large"
  ami_type     = local._arm ? "AL2023_ARM_64_STANDARD" : "AL2023_x86_64_STANDARD"
  spot_pool    = local._arm ? ["t4g.large", "t4g.xlarge", "m6g.large", "m7g.large"] : ["t3.large", "t3a.large", "m5.large", "m6i.large"]
}

inputs = {
  create       = true
  cluster_name = dependency.eks.outputs.cluster_id

  # Cost-profile: restrict every node group to a single AZ (the module slices subnet_ids). gp3 is
  # WaitForFirstConsumer so volumes follow the pods. include.base.locals.single_az_nodes (common.hcl).
  single_az = include.base.locals.single_az_nodes

  node_groups = {
    # System nodes run platform components (Cilium, Crossplane tenant control plane, Falco, cert-manager, etc.)
    system = {
      subnet_ids     = [for name, id in dependency.networking.outputs.subnet_ids : id if can(regex("kubernetes$", name))]
      instance_types = [local.sys_instance] # 2 vCPU / 8 GiB (t4g.large Graviton in the dev profile)
      ami_type       = local.ami_type
      # Dev profile: 1 node (minimal always-on; preprod is lighter — no observability/Keycloak/Backstage).
      # Crossplane's tenant control plane + Falco are RAM-heavy, so bump to 2 if pods stay Pending.
      desired_size = 1
      max_size     = 2
      min_size     = 1
      labels       = { "node-role" = "system" }
      # Cilium overlay decouples pods from ENI IPs; lift the kubelet cap off the ENI default (~35) to the
      # Kubernetes default so density is bound by CPU/mem, not IPs.
      max_pods = 110
    }
    # Workload nodes run tenant application pods — Spot in the dev profile (stateless; diversified pool).
    workload = {
      subnet_ids     = [for name, id in dependency.networking.outputs.subnet_ids : id if can(regex("kubernetes$", name))]
      instance_types = local.spot_pool
      ami_type       = local.ami_type
      capacity_type  = "SPOT"
      desired_size   = 1
      max_size       = 6
      min_size       = 1
      labels         = { "node-role" = "workload" }
      max_pods       = 110 # overlay: lift the ENI-based cap (see system node group)
    }
  }

  tags = include.base.locals.tags
}
