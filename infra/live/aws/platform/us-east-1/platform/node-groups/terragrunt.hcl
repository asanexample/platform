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

inputs = {
  create       = true
  cluster_name = dependency.eks.outputs.cluster_id

  node_groups = {
    # System nodes run platform components (Cilium, ArgoCD, cert-manager, etc.)
    system = {
      subnet_ids     = [for name, id in dependency.networking.outputs.subnet_ids : id if can(regex("kubernetes$", name))]
      instance_types = ["t3.large"] # 2 vCPU / 8 GiB — sufficient for platform workloads
      # 3 nodes so the ASG covers all 3 AZs — single-replica observability StatefulSets
      # (Mimir ingester/store-gateway, Prometheus) have AZ-pinned EBS volumes and need a
      # node in each AZ to schedule. 2 nodes across 3 AZs always left one AZ uncovered.
      desired_size = 3
      max_size     = 4
      min_size     = 3
      labels       = { "node-role" = "system" }
      # Cilium overlay decouples pods from ENI IPs; lift the kubelet cap off the t3.large
      # ENI default (~35) to the Kubernetes default so density is bound by CPU/mem, not IPs.
      max_pods = 110
    }
    # Workload nodes run ArgoCD-managed application pods
    workload = {
      subnet_ids     = [for name, id in dependency.networking.outputs.subnet_ids : id if can(regex("kubernetes$", name))]
      instance_types = ["t3.large"]
      desired_size   = 1
      max_size       = 6
      min_size       = 1
      labels         = { "node-role" = "workload" }
      max_pods       = 110 # overlay: lift the ENI-based cap (see system node group)
    }
  }

  tags = include.base.locals.tags
}
