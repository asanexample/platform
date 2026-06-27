include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.platform_directory
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

# CloudNativePG operator must exist before the directory DB Cluster CR is applied.
dependency "cloudnative_pg" {
  config_path = "../cloudnative-pg"

  mock_outputs                            = {}
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# Cilium provides the CiliumNetworkPolicy CRD the module uses to gate DB access to the agent's namespace.
dependency "cilium" {
  config_path = "../cilium"

  mock_outputs                            = {}
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

  # The directory's Postgres (ADR-084 Phase 1). Module defaults place it in the platform-infra `platform-directory`
  # namespace (no tenant label → not tenant-policed, like keycloak/backstage) and gate access to the triage agent's
  # namespace. The connection string is published to platform/triage-copilot/directory-db for the agent's ESO.

  # Teardown: drain the CNPG Cluster + PVC finalizers before the namespace delete (else it hangs Terminating).
  finalizer_clear_script = "${get_repo_root()}/scripts/k8s-finalizer-clear.sh"
  cluster_name           = dependency.eks.outputs.cluster_id
  region                 = include.base.locals.region
  deployer_role_arn      = include.base.locals.deployer_role_arn

  tags = include.base.locals.tags
}
