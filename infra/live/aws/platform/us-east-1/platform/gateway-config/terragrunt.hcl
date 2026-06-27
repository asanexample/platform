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
    # Routed directly to the Backstage Service on 7007 — Backstage authenticates each request itself via
    # direct Keycloak OIDC, so the oauth2-proxy front (and Dex) are retired.
    backstage = {
      namespace = "backstage"
      service   = "backstage"
      port      = 7007
    }
    # Argo Rollouts web UI (ADR-056) — live operator view of THIS cluster's rollouts, behind Keycloak SSO.
    # Routes to the oauth2-proxy (rollouts-sso unit), NOT the dashboard directly — the UI has no native auth, so
    # the proxy authenticates every request before forwarding to argo-rollouts-dashboard. Tailscale-only.
    rollouts = {
      namespace = "argo-rollouts"
      service   = "rollouts" # the oauth2-proxy Service
      port      = 80
    }
    # NOTE: the `keycloak` route is NOT here — Keycloak self-owns its HTTPRoute in the keycloak module (ADR-059)
    # so its endpoint is live before keycloak-config configures the realm through it.
  }
}
