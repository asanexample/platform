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
  grants_dir = "${get_repo_root()}/gitops/grants"
  envs_dir   = "${get_repo_root()}/gitops/environments"

  # Cross-team observability read grants, DERIVED from the AccessGrant registry (ADR-068). An obs grant
  # is projected at TEAM granularity — the tenant is per-team — so it exposes the owner team's ENTIRE
  # telemetry tenant. Two guards flow from that:
  #   1. Regulated exclusion (decision b): a team with ANY pci/hipaa environment is never a shareable
  #      owner — one regulated environment taints the whole team tenant for cross-team reads.
  #   2. Only `group:team-<X>` subjects are honored (no ad-hoc groups; matches the AccessGrant/Kyverno
  #      contract), and the grantee key is the bare team group the proxy sees in the token's `groups`.
  all_envs = [for f in fileset(local.envs_dir, "**/*.yaml") : yamldecode(file("${local.envs_dir}/${f}"))]
  regulated_teams = toset([
    for e in local.all_envs : e.spec.team if contains(["pci", "hipaa"], try(e.spec.tier, "standard"))
  ])

  access_grants = [for f in fileset(local.grants_dir, "**/*.yaml") : yamldecode(file("${local.grants_dir}/${f}"))]
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
  # RETIRED (#1269): the P13 read-proxy is decommissioned — OSS Grafana's oauthPassThru identity forwarding
  # is unreliable, so the mimir/loki datasources went back to direct-with-static-tenant-header and this proxy
  # is unused (see the mimir unit's read_proxy_url). Kept in git (not deleted) so re-enabling is a one-line
  # flip if forwarding is ever fixed. `create = false` tears down the now-inert Deployment/Service/ServiceMonitor.
  create = false

  namespace = dependency.observability.outputs.namespace

  # Digest-pinned signed image (built + cosign-signed by tenant-proxy-image.yml → platform ECR). Bump this
  # digest to the build output and re-apply (ADR-071 digest-pin). MUST be the INDEX digest (the one the
  # workflow's `steps.build.outputs.digest` reports, tagged with the git sha) — NOT the `.att`/`.sig`
  # single-manifests, which are unrunnable (empty config → "no command specified"). Current: the
  # multi-source identity build (X-Id-Token → Authorization Bearer→/userinfo fallback, #1269).
  image = "829808296602.dkr.ecr.us-east-1.amazonaws.com/platform/tenant-proxy@sha256:61534662a2913bf69c57d85225d5189c5efe905358de9b567daf535e1dc6c13c"

  # Every tenant present on the hub Mimir: the per-team tenants populated by the cortex-tenant write side
  # (alpha, bravo) + the two cluster tenants (`platform` = the hub's own metrics, `preprod` = the spoke's
  # force-stamped copy). A user's groups are intersected with this set (a non-team group can't widen access);
  # admin (platform-admins) federates over ALL of them, so an admin sees every cluster + team tenant.
  tenants     = ["alpha", "bravo", "platform", "preprod"]
  admin_group = "platform-admins"

  # Cross-team read grants derived from gitops/grants (ADR-068 AccessGrant), regulated owners excluded.
  # Empty today (no grants authored) ⇒ own-tenant-only; add an AccessGrant to open a cross-team read.
  grants = local.obs_grants

  # The mimir unit now renders the enforced `mimir` + `mimir-all` datasources pointed at this proxy
  # (read_proxy_url), so the proxy's own redundant `Mimir (my team)` datasource is disabled — one canonical
  # set of proxy-fronted metrics datasources, nothing un-proxied for a user to pick.
  create_datasource = false

  tags = include.base.locals.tags
}
