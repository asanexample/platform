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
  # v3 cutover (ADR-067/069 §6): the Product registry (gitops/products/<team>/<product>.yaml) is the sole source
  # of the per-PRODUCT supply-chain identities. metadata.name = <team>-<product>; spec.{team,repo} drive the
  # cosign/attestation gate. Replaces the v2 per-team derivation from gitops/tenant-claims (removed this cutover).
  products_dir = "${get_repo_root()}/gitops/products"
  products = { for f in fileset(local.products_dir, "**/*.yaml") :
    yamldecode(file("${local.products_dir}/${f}")).metadata.name => yamldecode(file("${local.products_dir}/${f}"))
  }

  # Tenant images live in the platform account's ECR (apps push there — see #60).
  ecr_registry = "${include.base.locals.account_ids["platform"]}.dkr.ecr.${include.base.locals.region}.amazonaws.com"

  # Per-PRODUCT cosign keyless verification (verify-images-product + verify-attestations-product): the shared
  # trusted-ci signer model, gated to each product by the cert's githubWorkflowRepository extension (= spec.repo).
  verify_subjects_product = { for name, p in local.products : name => {
    team           = p.spec.team
    product        = trimprefix(name, "${p.spec.team}-")
    repo           = p.spec.repo
    registryPrefix = "${local.ecr_registry}/team-${p.spec.team}/${trimprefix(name, "${p.spec.team}-")}"
  } }
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

  # Cluster-wide tenant image floor. v3: restrict-images / restrict-route-hostnames are owned PER-ENVIRONMENT by
  # the Crossplane Composition (product-scoped), so the chart renders no per-team versions — tenant_registry_map
  # + migrated_teams are empty (the v2 per-team supply-chain maps are removed this cutover).
  allowed_registries  = [local.ecr_registry]
  tenant_registry_map = {}
  migrated_teams      = []

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

  # v3 (ADR-067/069 §6): per-PRODUCT cosign keyless verification (verify-images-product +
  # verify-attestations-product), derived from the Product registry above. Every product uses the SHARED
  # trusted-ci build-sign (signature + SBOM) and slsa-provenance (provenance) workflows, gated to the product by
  # the cert's githubWorkflowRepository extension (= spec.repo). The v2 per-team verify_subjects / attest_caller_repos
  # / shared_signer_caller_repos are emptied (removed this cutover) — the product policies replace them.
  verify_subjects            = {}
  verify_subjects_product    = local.verify_subjects_product
  attest_caller_repos        = {}
  shared_signer_caller_repos = {}

  # Phase 5 — Gateway-API route hostname guard. v3: the Composition owns restrict-route-hostnames per-Environment
  # (product-scoped, ADR-067/069 §2), so the chart renders no per-team guard — this map is empty.
  enable_httproute_guard   = true
  tenant_hostname_patterns = {}
  enable_cleanup           = true

  tags = include.base.locals.tags
}
