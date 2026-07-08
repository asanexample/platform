include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.observability_tenant_proxy
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

# Deploys into the shared observability namespace, next to Grafana + Mimir.
dependency "observability" {
  config_path = "../observability"

  mock_outputs = {
    namespace = "observability"
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
  # P13 read-isolation toggle (enable_per_team_tenants) — on for the platform hub (env.hcl), where Grafana runs.
  create = include.base.locals.enable_per_team_tenants

  namespace = dependency.observability.outputs.namespace

  # Digest-pinned signed image (built + cosign-signed by tenant-proxy-image.yml → platform ECR). Bump this
  # digest to the build output and re-apply (ADR-071 digest-pin). MUST be the INDEX digest (the one the
  # workflow's `steps.build.outputs.digest` reports, tagged with the git sha) — NOT the `.att`/`.sig`
  # single-manifests, which are unrunnable (empty config → "no command specified"). Current: first build.
  image = "829808296602.dkr.ecr.us-east-1.amazonaws.com/platform/tenant-proxy@sha256:99d8c3698315bf2833f1169f64b56536d59a8ea65484a78c8da7663ddb0ba953"

  # Every tenant present on the hub Mimir: the per-team tenants populated by the cortex-tenant write side
  # (alpha, bravo) + the two cluster tenants (`platform` = the hub's own metrics, `preprod` = the spoke's
  # force-stamped copy). A user's groups are intersected with this set (a non-team group can't widen access);
  # admin (platform-admins) federates over ALL of them, so an admin sees every cluster + team tenant.
  tenants     = ["alpha", "bravo", "platform", "preprod"]
  admin_group = "platform-admins"

  # The mimir unit now renders the enforced `mimir` + `mimir-all` datasources pointed at this proxy
  # (read_proxy_url), so the proxy's own redundant `Mimir (my team)` datasource is disabled — one canonical
  # set of proxy-fronted metrics datasources, nothing un-proxied for a user to pick.
  create_datasource = false

  tags = include.base.locals.tags
}
