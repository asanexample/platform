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

# Foundational shared Gateway + ClusterIssuer (ADR-053/059). Created EARLY — no app deps — so per-app HTTPRoutes
# (and keycloak-config, which configures Keycloak through its gateway-exposed endpoint) have ingress available.
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
  domain   = "aws.refplat.org"
  internal = true # Internal NLB — platform services only reachable via Tailscale VPN

  letsencrypt_email      = include.base.locals.admin_email # Let's Encrypt certificate renewal notifications
  route53_hosted_zone_id = dependency.route53.outputs.zone_id
  route53_region         = include.base.locals.region

  # gateway_name / gateway_namespace / cluster_issuer_name use module defaults (platform-gateway / default /
  # letsencrypt-prod) — the contract every HTTPRoute parentRef depends on.
}
