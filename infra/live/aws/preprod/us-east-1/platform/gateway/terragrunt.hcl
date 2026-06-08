include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.gateway
}

# Foundational shared Gateway + ClusterIssuer for the preprod workload cluster (ADR-053/059). Created EARLY —
# no app deps — so tenant HTTPRoutes (delivered by ArgoCD into team-* namespaces) have ingress to attach to.
# Mirrors the platform gateway unit; preprod was missing this when the shared Gateway was split out of the
# gateway-config unit, so `preprod-gateway` (every tenant route's parentRef) had no creator.
dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_id                    = "mock-cluster"
    cluster_endpoint              = "https://mock-endpoint"
    cluster_certificate_authority = "bW9jaw=="
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

dependency "cilium" {
  config_path = "../cilium"

  mock_outputs                            = {}
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

dependency "cert_manager" {
  config_path = "../cert-manager"

  mock_outputs                            = {}
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

dependency "external_dns" {
  config_path = "../external-dns"

  mock_outputs                            = {}
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

dependency "route53" {
  config_path = "../route53"

  mock_outputs = {
    zone_id = "MOCK"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
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
  create   = true
  domain   = "preprod.aws.refplat.org" # preprod's delegated subdomain (tenant hostnames: <app>.preprod.aws.refplat.org)
  internal = false                     # Public (internet-facing) NLB — preprod tenant apps are reachable from the internet

  letsencrypt_email      = include.base.locals.admin_email
  route53_hosted_zone_id = dependency.route53.outputs.zone_id
  route53_region         = include.base.locals.region

  # gateway_name overrides the module default (platform-gateway) — tenant HTTPRoutes on preprod parentRef
  # `preprod-gateway` (namespace default). cluster_issuer_name uses the module default (letsencrypt-prod).
  gateway_name = "preprod-gateway"
}
