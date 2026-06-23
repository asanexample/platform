include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.observability_blackbox
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

dependency "node_groups" {
  config_path = "../node-groups"

  mock_outputs                            = {}
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# blackbox-exporter + the Probe CR live in the observability namespace; the hub Prometheus scrapes the Probe.
dependency "observability" {
  config_path = "../observability"

  mock_outputs = {
    namespace = "observability"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# Probe targets are the per-app HTTPRoutes on the shared Gateway — order after gateway-config so they're live.
dependency "gateway_config" {
  config_path = "../gateway-config"

  mock_outputs                            = {}
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# The shared Gateway — we point probes at its Envoy ClusterIP (via hostAliases) to bypass the internal-NLB
# hairpin. Cilium names the Service `cilium-gateway-<gateway-name>`.
dependency "gateway" {
  config_path = "../gateway"

  mock_outputs = {
    gateway_name      = "platform-gateway"
    gateway_namespace = "default"
  }
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
  create    = true
  namespace = dependency.observability.outputs.namespace

  helm_chart_version = include.base.locals.helm_versions.blackbox_exporter

  # External probes of the platform's user-facing endpoints (Tailscale-only internal NLB; the blackbox-exporter
  # reaches them in-VPC, through the real Gateway + TLS). They 302 to SSO / 200 when up.
  probe_targets = [
    "https://grafana.aws.refplat.org",
    "https://argocd.aws.refplat.org",
    "https://backstage.aws.refplat.org",
    "https://keycloak.aws.refplat.org",
  ]

  # Reach the Gateway Envoy directly (its ClusterIP) instead of hairpinning through the internal NLB.
  gateway_service_name      = "cilium-gateway-${dependency.gateway.outputs.gateway_name}"
  gateway_service_namespace = dependency.gateway.outputs.gateway_namespace

  tags = include.base.locals.tags
}
