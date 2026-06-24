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
    # Workload capacity is now Karpenter's (ADR-078) — the static Spot workload group is retired. Preprod's
    # `karpenter` unit is AGGRESSIVE (spot + WhenEmptyOrUnderutilized): it provisions spot nodes just-in-time
    # for tenant workloads and consolidates them when idle. The system group stays a fixed on-demand floor.
  }

  tags = include.base.locals.tags
}
