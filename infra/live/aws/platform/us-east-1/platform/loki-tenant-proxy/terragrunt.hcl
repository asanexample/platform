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

locals {
  # Same cross-team read-grant derivation as the metrics tenant-proxy (ADR-068 AccessGrant → per-team obs
  # read), regulated (pci/hipaa) owner teams excluded. Applies identically to logs.
  grants_dir = "${get_repo_root()}/gitops/grants"
  envs_dir   = "${get_repo_root()}/gitops/environments"

  all_envs = [for f in fileset(local.envs_dir, "**/*.yaml") : yamldecode(file("${local.envs_dir}/${f}"))]
  regulated_teams = toset([
    for e in local.all_envs : e.spec.team if contains(["pci", "hipaa"], try(e.spec.tier, "standard"))
  ])

  # gitops/grants/ holds more than one CRD kind (ADR-101 added ServiceGrant alongside AccessGrant, same
  # tree) — filter to AccessGrant before assuming `spec.subject` is a `group:team-<X>` string.
  all_grant_docs = [for f in fileset(local.grants_dir, "**/*.yaml") : yamldecode(file("${local.grants_dir}/${f}"))]
  access_grants  = [for d in local.all_grant_docs : d if try(d.kind, "") == "AccessGrant"]
  team_grants = [
    for g in local.access_grants : {
      grantee = trimprefix(g.spec.subject, "group:team-")
      owner   = g.spec.target.team
    }
    if startswith(try(g.spec.subject, ""), "group:team-") && !contains(local.regulated_teams, g.spec.target.team)
  ]
  obs_grants = {
    for grantee in distinct([for tg in local.team_grants : tg.grantee]) :
    grantee => distinct([for tg in local.team_grants : tg.owner if tg.grantee == grantee])
  }
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

# Deploys into the shared observability namespace, next to Grafana + Loki.
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
  # RETIRED (#1269), same as the metrics tenant-proxy — the loki datasources went back to direct read, so this
  # is inert. `create = false` tears it down; re-enable by restoring the loki unit's read_proxy_url + this gate.
  create = false

  # A per-signal instance of the SAME grant-aware proxy image, fronting Loki instead of Mimir.
  name      = "loki-tenant-proxy"
  namespace = dependency.observability.outputs.namespace

  # Same digest-pinned signed image as the metrics tenant-proxy (signal-agnostic; only the upstream differs).
  image = "829808296602.dkr.ecr.us-east-1.amazonaws.com/platform/tenant-proxy@sha256:61534662a2913bf69c57d85225d5189c5efe905358de9b567daf535e1dc6c13c"

  # The Loki query gateway (Grafana's Loki datasource appends /loki/api/v1/...). Identity-scoped X-Scope-OrgID.
  upstream_url = "http://loki-gateway.observability.svc"

  tenants     = ["alpha", "bravo", "platform", "preprod"]
  admin_group = "platform-admins"
  grants      = local.obs_grants

  # The loki module renders the enforced `loki` + `loki-all` datasources pointed here; no redundant one.
  create_datasource = false

  tags = include.base.locals.tags
}
