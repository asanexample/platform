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

  # Teams whose app CI calls asanexample/trusted-ci's slsa-provenance.yml as the SOLE provenance signer
  # (SLSA L3, #131). For these teams verify-attestations requires trusted-ci-signed provenance instead of
  # app-signed. Add a team here ONLY once its CI has dropped the hand-authored provenance step and wired
  # the trusted-ci job — otherwise its images fail the provenance check. (Later: a teams.hcl per-app flag.)
  isolated_provenance_teams = ["alpha", "bravo"]

  # Teams whose app CI builds+signs the image (and SBOM) via the SHARED trusted-ci build-sign.yml reusable
  # workflow (a thin caller — the supply-chain backbone abstracted out of per-app deploy.yml). For these
  # teams verify-images and the verify-attestations SBOM ALSO accept the shared-signer identity (gated by
  # the githubWorkflowRepository extension = the app repo), in addition to any app-signed identity. Add a
  # team here once its deploy.yml/preview.yml call build-sign.yml. Bespoke apps that self-build stay
  # app-signed (absent here). Mirrors isolated_provenance_teams (provenance).
  shared_signer_teams = ["alpha", "bravo"]
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

  # Cilium overlay (cluster-pool) datapath: the EKS managed control plane can't route to overlay
  # pod IPs, so the admission/cleanup webhook servers must run on hostNetwork (node VPC IP).
  webhook_host_network = true

  # Cluster-wide tenant image floor + per-team scoping (team data stays at the unit level).
  allowed_registries  = [local.ecr_registry]
  tenant_registry_map = { for k, v in local.teams : k => "${local.ecr_registry}/team-${k}" }
  # Teams migrated to a Tenant claim (BACK stack P3): the chart skips their per-team restrict-images /
  # restrict-route-hostnames policies (the Composition owns those), but keeps verify-images/attestations.
  migrated_teams = local.teams_config.locals.migrated_teams

  # Crossplane (the federated tenant control plane, ADR-046/048) runs here. Its rbac-manager authors wildcard
  # provider ClusterRoles at runtime as its own ServiceAccount (not the deployer), which the cluster-scoped
  # restrict-wildcard-rbac policy would otherwise deny in Enforce — blocking the install. Exclude the
  # crossplane-system control-plane principals (justified like kube-system/argocd) and the namespace. MUST be
  # applied before the crossplane unit.
  extra_exclude_principals = ["system:serviceaccount:crossplane-system:*"]
  extra_exclude_namespaces = ["crossplane-system"]

  helm_chart_version = include.base.locals.helm_versions.kyverno
  helm_wait          = true

  # Phase 3 — cosign keyless image verification (Audit-first, independent of the Enforce above).
  enable_image_verification = true
  verify_failure_action     = "Enforce"
  # SBOM + SLSA provenance attestation requirement (#108/108d). Enforce: non-compliant tenant images are
  # rejected at admission. For adopted teams the SLSA provenance must be trusted-ci-signed (see
  # attest_caller_repos below). Re-flipped to Enforce 2026-05-30 after the SLSA L3 single-provenance
  # cutover (#131): the new trusted-ci-provenance alpha image (sha256:d1e942d0) verified clean under Audit
  # (PolicyReport verifiedCount:1, pods rolled out) so Enforce no longer risks blocking the live workload.
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

  # SLSA Build L3 (#131, ADR-042): for adopted teams (local.isolated_provenance_teams), verify-attestations
  # requires the SLSA provenance to be signed by the ISOLATED trusted-ci reusable workflow instead of the
  # app's own — gated per-team by the cert's githubWorkflowRepository extension (= the team's app repo).
  # The app dropped its hand-authored provenance step, so each image carries a SINGLE slsaprovenance
  # attestation (trusted-ci) → a clean one-identity match. (Replaced the dead separate-Audit-policy
  # approach: two slsaprovenance attestations of different identities ERROR Kyverno's matching →
  # verifiedCount:0.) SBOM stays app-signed.
  attest_caller_repos = { for k in local.isolated_provenance_teams :
    k => replace(values(local.teams[k].apps)[0].repo_url, "https://github.com/", "")
  }

  # Shared build-sign signer (the thin-caller supply-chain abstraction): for these teams verify-images and
  # the verify-attestations SBOM ALSO accept the shared trusted-ci/build-sign.yml identity, gated by the
  # githubWorkflowRepository extension (= the app repo). Derived like attest_caller_repos. The default
  # trusted_ci_build_subject_regexp in the module matches build-sign.yml at any pinned ref.
  shared_signer_caller_repos = { for k in local.shared_signer_teams :
    k => replace(values(local.teams[k].apps)[0].repo_url, "https://github.com/", "")
  }

  # Phase 5 — Gateway-API route hostname guard (anti-squatting on the shared wildcard listener).
  # For MIGRATED teams the Crossplane Tenant Composition owns restrict-route-hostnames (derived from the
  # XTenant claim, ADR-060/061), so the chart skips them here — this map is the fallback for any
  # not-yet-migrated team. teams.hcl no longer carries hostnames; default to [] when absent.
  enable_httproute_guard   = true
  tenant_hostname_patterns = { for k, v in local.teams : k => try(v.hostnames, []) }
  enable_cleanup           = true

  tags = include.base.locals.tags
}
