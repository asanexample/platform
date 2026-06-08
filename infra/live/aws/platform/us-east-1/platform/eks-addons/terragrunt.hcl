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
    cluster_id                    = "mock-cluster"
    cluster_endpoint              = "https://mock-endpoint"
    cluster_certificate_authority = "bW9jaw=="
    oidc_provider_arn             = "arn:aws:iam::000000000000:oidc-provider/mock"
    oidc_provider_url             = "oidc.eks.mock.amazonaws.com/id/mock"
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

# Kubernetes provider for the gp3 default StorageClass (exec auth → PlatformDeployer).
generate "kubernetes_provider" {
  path      = "kubernetes-provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "kubernetes" {
      host                   = "${dependency.eks.outputs.cluster_endpoint}"
      cluster_ca_certificate = base64decode("${dependency.eks.outputs.cluster_certificate_authority}")

      exec {
        api_version = "client.authentication.k8s.io/v1beta1"
        command     = "aws"
        args        = ["eks", "get-token", "--cluster-name", "${dependency.eks.outputs.cluster_id}", "--region", "${include.base.locals.region}", "--role-arn", "${include.base.locals.deployer_role_arn}"]
      }
    }
  EOF
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
    # Serves workload AWS credentials via EKS Pod Identity associations (ADR-041). Required by Crossplane
    # (the tenant control plane, ADR-046), whose AWS provider authenticates via Pod Identity. Platform
    # add-ons otherwise use IRSA; this brings the hub cluster in line with preprod. AWS-managed DaemonSet.
    eks-pod-identity-agent = {}
    # Serves the metrics.k8s.io API (`kubectl top`, HPA resource metrics). The platform's observability stack
    # (kube-prometheus-stack) covers dashboards/alerting but does NOT provide this API, so without this addon
    # `kubectl top` and any HPA are unavailable. No IRSA — reads the kubelet summary API only.
    # hostNetwork: the EKS control plane can't reach overlay (Cilium BYOCNI) pod IPs, so a default (ClusterIP)
    # metrics-server fails the aggregated-API discovery check (FailedDiscoveryCheck) — same wall the Crossplane
    # providers + Kyverno webhooks hit. On hostNetwork the apiserver reaches it via the routable node IP.
    # containerPort default (10251) is free on worker nodes (kube-scheduler runs on the managed control plane).
    metrics-server = {
      configuration_values = jsonencode({ hostNetwork = { enabled = true } })
    }
  }

  # gp3 cluster-default StorageClass for dynamic PVCs (observability hub / Mimir, #102 P2).
  create_default_storageclass = true

  tags = include.base.locals.tags
}
