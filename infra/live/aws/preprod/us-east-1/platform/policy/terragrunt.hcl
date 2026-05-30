include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.policy
}

locals {
  teams_config = read_terragrunt_config("${get_terragrunt_dir()}/../teams.hcl")
  teams        = local.teams_config.locals.teams

  # Tenant images live in the platform account's ECR (apps push there — see #60).
  ecr_registry = "${include.base.locals.account_ids["platform"]}.dkr.ecr.${include.base.locals.region}.amazonaws.com"

  # Cosign identity transition complete (2026-05-29): app-alpha re-signed under asanexample and the
  # running image (sha256:d60ea84) verified, so the legacy gangster identity is dropped. Left empty (not
  # removed) to keep the dual-subject scaffold documented and reusable for the next org/identity change.
  legacy_org = ""

  # Teams whose app CI calls asanexample/trusted-ci's slsa-provenance.yml (SLSA L3, #131). Drives the
  # Audit-only verify-attestations-l3 policy. Add a team here ONLY once its CI wires the provenance job —
  # otherwise its pods get spurious Audit failures. P1 wired alpha. (Later: a teams.hcl per-app flag.)
  isolated_provenance_teams = ["alpha"]
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

inputs = {
  create = true

  # Enforce: reject violations at admission (webhook fails closed). Flipped after the Audit phase
  # confirmed PolicyReports clean against the live alpha workload (ADR-014 rollout).
  validation_failure_action = "Enforce"

  compliance_tier = include.base.locals.compliance_tier
  replica_count   = 1 # non-prod; platform runs 3 for HA

  # Cluster-wide tenant image floor + per-team scoping (team data stays at the unit level).
  allowed_registries  = [local.ecr_registry]
  tenant_registry_map = { for k, v in local.teams : k => "${local.ecr_registry}/team-${k}" }

  helm_chart_version = include.base.locals.helm_versions.kyverno
  helm_wait          = true

  # Phase 3 — cosign keyless image verification (Audit-first, independent of the Enforce above).
  enable_image_verification = true
  verify_failure_action     = "Enforce"
  # SBOM + SLSA provenance attestation requirement (#108/108d). Flipped to Enforce after the Audit
  # phase confirmed the live alpha deploy + PR-preview images verify ("image verified" PolicyReport).
  enable_attestation_verification = true
  attest_failure_action           = "Enforce"
  oidc_provider_arn               = dependency.eks.outputs.oidc_provider_arn
  oidc_provider_url               = dependency.eks.outputs.oidc_provider_url
  ecr_account_id                  = include.base.locals.account_ids["platform"]
  # Per-team cosign keyless identities derived from each team's app repo (team data stays at the unit).
  # A LIST per team (count:1 attestor): the asanexample identity plus, during the org migration, the
  # legacy gangster identity (same repo path under the old org). distinct/compact collapse the legacy
  # entry away once local.legacy_org = "".
  verify_subjects = { for k, v in local.teams : k => [
    for url in distinct(compact([
      values(v.apps)[0].repo_url,
      local.legacy_org == "" ? "" : replace(values(v.apps)[0].repo_url, "asanexample", local.legacy_org),
      ])) : {
      deploy_subject         = "${url}/.github/workflows/deploy.yml@refs/heads/main"
      preview_subject_regexp = "${url}/.github/workflows/preview.yml@refs/.*"
    }
  ] }

  # SLSA Build L3 P2 (#131, ADR-042): Audit-only check that the ISOLATED trusted-ci signer's provenance
  # verifies, gated per-team by the cert's githubWorkflowRepository extension (the caller = the team's
  # own app repo). Runs alongside the Enforce app-provenance policy; PolicyReports confirm the trusted-ci
  # path before P3 enforces it. Only for adopted teams (local.isolated_provenance_teams).
  enable_l3_provenance_audit = true
  attest_caller_repos = { for k in local.isolated_provenance_teams :
    k => replace(values(local.teams[k].apps)[0].repo_url, "https://github.com/", "")
  }

  # Phase 5 — Gateway-API route hostname guard (anti-squatting on the shared wildcard listener).
  # Each team's routes may only claim the hostnames it declares in teams.hcl. (When PR previews get a
  # dedicated preview_domain, add an app-scoped "<app>-pr-*.<domain>" pattern here.)
  enable_httproute_guard   = true
  tenant_hostname_patterns = { for k, v in local.teams : k => v.hostnames }
  enable_cleanup           = true

  tags = include.base.locals.tags
}
