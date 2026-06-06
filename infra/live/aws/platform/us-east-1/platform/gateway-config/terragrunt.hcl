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

# The foundational Gateway + ClusterIssuer live in the `gateway` unit (ADR-053/059); this unit owns only the
# per-app routes and attaches them to that Gateway by name.
dependency "gateway" {
  config_path = "../gateway"

  mock_outputs = {
    gateway_name      = "platform-gateway"
    gateway_namespace = "default"
  }
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
  create = true
  domain = "aws.refplat.org"

  # The shared Gateway is owned by the `gateway` unit; attach routes to it by name.
  gateway_name      = dependency.gateway.outputs.gateway_name
  gateway_namespace = dependency.gateway.outputs.gateway_namespace

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
    # NOTE: the `keycloak` route is NOT here — Keycloak self-owns its HTTPRoute in the keycloak module (ADR-059)
    # so its endpoint is live before keycloak-config configures the realm through it.
  }
}
