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
  # Graviton (arm64/t4g) vs x86 (t3), driven by include.base.locals.node_arch. (Subnet/single-AZ selection
  # can't live here — terragrunt locals can't read dependency outputs — so it's passed to the module as
  # single_az + the full kubernetes subnet list; the module restricts to one AZ when single_az = true.)
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
    # System nodes run platform components (Cilium, ArgoCD, cert-manager, Keycloak, Crossplane, etc.)
    system = {
      subnet_ids     = [for name, id in dependency.networking.outputs.subnet_ids : id if can(regex("kubernetes$", name))]
      instance_types = [local.sys_instance] # 2 vCPU / 8 GiB (t4g.large Graviton in the dev profile)
      ami_type       = local.ami_type
      # Dev profile: 2 nodes. With Mimir off and single-AZ placement, the old "cover all 3 AZs for the
      # AZ-pinned observability StatefulSets" reason is gone — count is now RAM/CPU-bound. The stack is
      # heavy (Keycloak JVM, ArgoCD, Crossplane, Backstage, Prometheus); bump to 3 if pods stay Pending.
      desired_size = 2
      max_size     = 3
      min_size     = 2
      labels       = { "node-role" = "system" }
      # Cilium overlay decouples pods from ENI IPs; lift the kubelet cap off the ENI default (~35) to the
      # Kubernetes default so density is bound by CPU/mem, not IPs.
      max_pods = 110
    }
    # Workload capacity is now Karpenter's (ADR-078) — the static Spot workload group is retired. Karpenter
    # provisions right-sized on-demand nodes just-in-time for overflow and consolidates them when idle (the
    # `karpenter` unit). The system group stays a fixed on-demand floor for the controller + standing components.
  }

  tags = include.base.locals.tags
}
