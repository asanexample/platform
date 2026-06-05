include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.gateway_config
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

dependency "argocd" {
  config_path = "../argocd"

  mock_outputs = {
    namespace = "argocd"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# The `sso` HTTPRoute is created in the dex namespace, so Dex must exist first.
dependency "dex" {
  config_path = "../dex"

  mock_outputs = {
    namespace    = "dex"
    service_name = "dex"
    service_port = 5556
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# The `keycloak` HTTPRoute is created in the keycloak namespace (ADR-053, B1 — alongside Dex).
dependency "keycloak" {
  config_path = "../keycloak"

  mock_outputs = {
    namespace    = "keycloak"
    service_name = "keycloak"
    service_port = 80
  }
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

  routes = {
    argocd = {
      namespace = dependency.argocd.outputs.namespace
      service   = "argocd-server"
      port      = 80
    }
    # Observability hub (#102 P1) — Grafana, Tailscale-only at grafana.aws.refplat.org.
    grafana = {
      namespace = "observability"
      service   = "kube-prometheus-stack-grafana"
      port      = 80
    }
    # Developer portal (Backstage, Phase 2 — ADR-051). Tailscale-only at backstage.aws.refplat.org.
    # Fronted by oauth2-proxy (#202): the gateway routes to the proxy, which owns the durable session
    # cookie and forwards authenticated traffic to the backstage Service (same namespace) on 7007.
    backstage = {
      namespace = "backstage"
      service   = "oauth2-proxy"
      port      = 4180
    }
    # Centralized Dex SSO broker (Phase 2.1 — ADR-051). Tailscale-only at sso.aws.refplat.org;
    # OIDC issuer for Backstage (and future apps). TLS at the gateway; Dex listens HTTP on 5556.
    sso = {
      namespace = dependency.dex.outputs.namespace
      service   = dependency.dex.outputs.service_name
      port      = dependency.dex.outputs.service_port
    }
    # Keycloak app IdP (ADR-053, B1). Tailscale-only at keycloak.aws.refplat.org, alongside Dex's sso route;
    # becomes the sso.* issuer at the Dex cutover. TLS at the gateway; Keycloak Service serves HTTP on 80.
    keycloak = {
      namespace = dependency.keycloak.outputs.namespace
      service   = dependency.keycloak.outputs.service_name
      port      = dependency.keycloak.outputs.service_port
    }
  }
}
