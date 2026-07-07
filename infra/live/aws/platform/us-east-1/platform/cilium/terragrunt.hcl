include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.cilium
}

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_id                    = "mock-cluster"
    cluster_endpoint              = "https://mock-endpoint"
    cluster_certificate_authority = "bW9jaw=="
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

generate "kubeconfig" {
  path      = "kubeconfig.yaml"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    apiVersion: v1
    kind: Config
    clusters:
    - cluster:
        server: ${dependency.eks.outputs.cluster_endpoint}
        certificate-authority-data: ${dependency.eks.outputs.cluster_certificate_authority}
      name: default
    contexts:
    - context:
        cluster: default
        user: default
      name: default
    current-context: default
    users:
    - name: default
      user:
        exec:
          apiVersion: client.authentication.k8s.io/v1beta1
          command: aws
          args:
          - eks
          - get-token
          - --cluster-name
          - ${dependency.eks.outputs.cluster_id}
          - --region
          - ${include.base.locals.region}
          - --role-arn
          - ${include.base.locals.deployer_role_arn}
  EOF
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
  create          = true
  cloud_provider  = "aws"
  cluster_name    = dependency.eks.outputs.cluster_id
  kubeconfig_path = "kubeconfig.yaml"

  # Overlay datapath (cluster-pool IPAM + VXLAN). pod_cidr is authoritative in
  # network.hcl; ipam_mode/routing_mode/tunnel_protocol/pod_cidr_mask_size use the
  # module overlay defaults. Override here (e.g. ipam_mode = "eni") to use native.
  pod_cidr = include.base.locals.all_vars.pod_cidr

  k8s_service_host = replace(dependency.eks.outputs.cluster_endpoint, "https://", "")
  k8s_service_port = "443"

  helm_chart_version = include.base.locals.helm_versions.cilium
  # Must not wait — Cilium deploys before node groups exist (BYOCNI ordering)
  helm_wait = false

  # East-west transparent encryption (ADR-057 Phase 1): WireGuard, pod-to-pod, fleet-default.
  # Enabled on preprod first (verified 2026-07-07), then here. node_encryption deferred.
  encryption_enabled = true

  tags = include.base.locals.tags
}
