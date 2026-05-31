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
  }

  # gp3 cluster-default StorageClass for dynamic PVCs (observability hub / Mimir, #102 P2).
  create_default_storageclass = true

  tags = include.base.locals.tags
}
