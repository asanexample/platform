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
  # The platform cluster hosts shared services, not tenants — there is no teams.hcl here. The engine,
  # cluster-scoped hardening (RBAC, default-namespace), and the registry floor still apply.
  ecr_registry = "${include.base.locals.account_ids["platform"]}.dkr.ecr.${include.base.locals.region}.amazonaws.com"

  # Platform AGENTS run on the hub (ADR-082), so their images are admitted HERE — cosign-verify them with the
  # same per-Product verify-images/verify-attestations the preprod policy unit applies to tenants, but scoped to
  # ONLY the agent Products (gitops/agents → their Product), since tenants run on preprod, not here. Join to the
  # Product registry for spec.repo (the signer's githubWorkflowRepository identity). Empty until the first
  # XAgent claim lands. README.md is excluded (**/*.yaml).
  agents_dir   = "${get_repo_root()}/gitops/agents"
  products_dir = "${get_repo_root()}/gitops/products"
  agent_entries = [for f in fileset(local.agents_dir, "**/*.yaml") : {
    team    = yamldecode(file("${local.agents_dir}/${f}")).spec.team
    product = yamldecode(file("${local.agents_dir}/${f}")).spec.product
  }]
  verify_subjects_product = { for e in local.agent_entries : "${e.team}-${e.product}" => {
    team           = e.team
    product        = e.product
    repo           = yamldecode(file("${local.products_dir}/${e.team}/${e.product}.yaml")).spec.repo
    registryPrefix = "${local.ecr_registry}/team-${e.team}/${e.product}"
  } }
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

# CRD-before-policy (ADR-056): the availability policies match the `Rollout` kind (enable_rollout_kind below),
# and a Kyverno rule naming a kind whose CRD is absent fails to create (#7839). The argo-rollouts unit installs
# the CRDs, so policy must apply after it.
dependency "argo_rollouts" {
  config_path = "../argo-rollouts"

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
  cluster_name = dependency.eks.outputs.cluster_id
  create       = true

  # Enforce: webhook fails closed. Flipped after preprod was proven in Enforce and the cluster-scoped
  # RBAC policies were hardened to exempt the IaC deployer (validated on preprod: PlatformDeployer
  # cluster-admin binding denied -> admitted). ArgoCD + the deployer (the RBAC-creating actors here)
  # are in exclude_principals. See ADR-014 / kyverno-break-glass runbook.
  validation_failure_action = "Enforce"

  compliance_tier = include.base.locals.compliance_tier
  replica_count   = 3 # HA on the shared platform cluster

  # Cilium overlay (cluster-pool): the EKS managed control plane can't route to overlay pod IPs,
  # so the admission/cleanup webhook servers must run on hostNetwork (node VPC IP). Applied AFTER
  # the overlay cutover (hostNetwork needs the overlay cilium's kubeProxyReplacement to reach the apiserver).
  webhook_host_network = true

  allowed_registries = [local.ecr_registry] # no tenants on the platform cluster

  # Cosign verify-images/verify-attestations for the platform agents that run on the hub (ADR-082), now that the
  # triage-copilot XAgent (gitops/agents/triage-copilot.yaml) is live. Enforced — matching preprod. Rolled out
  # Audit-first and confirmed the agent's signed+attested image passes in-cluster (Kyverno PolicyReports showed
  # verify-images-product + verify-attestations-product = pass, "image verified") before this Enforce flip.
  # Attestation verification requires image verification (reuses the ECR-read Pod Identity).
  verify_subjects_product         = local.verify_subjects_product
  enable_image_verification       = true
  verify_failure_action           = "Enforce"
  enable_attestation_verification = true
  attest_failure_action           = "Enforce"

  # Crossplane (the tenant control plane, ADR-046) runs here. Its rbac-manager authors wildcard
  # provider ClusterRoles at runtime as its own ServiceAccount (not the deployer), which the
  # cluster-scoped restrict-wildcard-rbac policy would otherwise deny in Enforce — blocking the
  # install. Exclude the crossplane-system control-plane principals (justified like kube-system/argocd:
  # a platform RBAC controller, not a tenant) and the namespace. MUST be applied before the crossplane unit.
  # CloudNativePG (the Backstage DB operator, ADR-051) is the same case: its controller authors a
  # per-Cluster Role (in the app namespace) that restrict-wildcard-rbac flags — exclude the cnpg-system
  # operator principal (a trusted platform operator, not a tenant) so it can provision managed databases.
  # ARC (the self-hosted runner controller, ADR-065 / #323) is the same again: its controller authors a
  # per-listener Role in arc-runners that restrict-wildcard-rbac denies in Enforce — exclude the arc-systems
  # controller principal + the ARC namespaces (a trusted platform operator, not a tenant).
  extra_exclude_principals = [
    "system:serviceaccount:crossplane-system:*",
    "system:serviceaccount:cnpg-system:*",
    "system:serviceaccount:arc-systems:*",
  ]
  extra_exclude_namespaces = ["crossplane-system", "cnpg-system", "arc-systems", "arc-runners"]

  helm_chart_version = include.base.locals.helm_versions.kyverno
  helm_wait          = true

  # ADR-056: the availability policies also match the Argo `Rollout` kind. Safe to enable now that the
  # argo-rollouts unit (CRDs) is applied here (see the dependency above; #7839).
  enable_rollout_kind = true

  tags = include.base.locals.tags
}
