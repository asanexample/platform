include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.eks_addons
}

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_id        = "mock-cluster"
    oidc_provider_arn = "arn:aws:iam::000000000000:oidc-provider/mock"
    oidc_provider_url = "oidc.eks.mock.amazonaws.com/id/mock"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

dependency "cilium" {
  config_path = "../cilium"

  mock_outputs                            = {}
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

dependency "node_groups" {
  config_path = "../node-groups"

  mock_outputs                            = {}
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

inputs = {
  create       = true
  cluster_name = dependency.eks.outputs.cluster_id

  oidc_provider_arn = dependency.eks.outputs.oidc_provider_arn
  oidc_provider_url = dependency.eks.outputs.oidc_provider_url

  addons = {
    coredns = {}
    aws-ebs-csi-driver = {
      irsa = {
        service_account_name      = "ebs-csi-controller-sa"
        service_account_namespace = "kube-system"
        policy_arns               = ["arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"]
      }
    }
    # Serves per-team workload AWS credentials via Pod Identity associations (ADR-041). No IRSA — runs
    # as a DaemonSet AWS manages. Required by the pod-identity unit.
    eks-pod-identity-agent = {}
    # Serves the metrics.k8s.io API (`kubectl top`, HPA). kube-prometheus-stack covers dashboards but not this
    # API. No IRSA — reads the kubelet summary API only. hostNetwork: the EKS control plane can't reach overlay
    # (Cilium BYOCNI) pod IPs, so a default metrics-server fails aggregated-API discovery; on hostNetwork the
    # apiserver reaches it via the node IP (same pattern as the Crossplane providers / Kyverno webhooks).
    metrics-server = {
      configuration_values = jsonencode({ hostNetwork = { enabled = true } })
    }
  }

  tags = include.base.locals.tags
}
