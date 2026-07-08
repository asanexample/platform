include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.observability_loki
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

dependency "node_groups" {
  config_path = "../node-groups"

  mock_outputs                            = {}
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# Loki deploys into the observability namespace (shares Grafana's datasource sidecar + the
# default-deny NetworkPolicy isolation). Depend on observability so the namespace exists first.
dependency "observability" {
  config_path = "../observability"

  mock_outputs = {
    namespace = "observability"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# Shared Cilium Gateway — Loki self-routes its cross-cluster spoke-ingest HTTPRoute onto it (#627).
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
  # Cost-profile toggle: off in dev. Flip enable_loki in common.hcl to deploy it. create=false applies as a
  # no-op (empty state, skipped on teardown).
  create       = include.base.locals.enable_loki
  cluster_name = dependency.eks.outputs.cluster_id
  aws_region   = include.base.locals.region

  namespace = dependency.observability.outputs.namespace

  # Identity = EKS Pod Identity (ADR-047): the module creates the role + association from cluster_name +
  # namespace + the chart SA. No OIDC provider inputs (unlike the IRSA-based mimir unit).

  helm_chart_version = include.base.locals.helm_versions.loki
  helm_wait          = true

  # Sizing follows cost_profile (dev = single-binary minimal; prod = SimpleScalable RF3).
  high_availability = include.base.locals.high_availability
  storage_class     = "gp3"

  # Retention bumped 14d→45d for the agent-eval capture substrate (ADR-080 D6): gives a grace window for
  # label back-fill (an incident's RCA / accept-reject can land weeks after it fires) plus a modest
  # live-backtest window. Loki here is ~sub-GB, so the extra retention is ~free. (Tempo stays at its 3d
  # default — traces are the priciest, least label-dense store, and forward-capture freezes the snapshot.)
  retention_period = "1080h" # 45d (module default 336h/14d)

  # Cross-cluster log spoke ingest (#627): self-route a write-only, tenant-overwriting HTTPRoute per spoke +
  # surface each spoke's tenant (and a federated all-clusters view) as Grafana datasources.
  spoke_ingest = {
    domain            = "aws.refplat.org"
    gateway_name      = dependency.gateway.outputs.gateway_name
    gateway_namespace = dependency.gateway.outputs.gateway_namespace
    tenants           = { preprod = "preprod" }
  }
  extra_tenant_datasources    = ["preprod"]
  enable_federated_datasource = true

  # P13 enforcement (#590), mirroring metrics: route the Grafana Loki datasources through the loki-tenant-proxy
  # (identity-scoped) instead of direct headers, and let the spoke edge PASS THROUGH the per-team tenant the
  # preprod Alloy stamps (instead of force-stamping `preprod`). Both gated on the per-team-tenants flag.
  read_proxy_url           = include.base.locals.enable_per_team_tenants ? "http://loki-tenant-proxy.observability.svc:8080" : ""
  spoke_ingest_passthrough = include.base.locals.enable_per_team_tenants

  tags = include.base.locals.tags
}
