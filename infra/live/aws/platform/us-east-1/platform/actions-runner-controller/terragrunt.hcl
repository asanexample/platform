include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.actions_runner_controller
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

# The GitHub App credential is synced by an ExternalSecret, so the ESO operator (external-secrets) and the
# ClusterSecretStore (secret-stores) must exist first.
dependency "external_secrets" {
  config_path = "../external-secrets"

  mock_outputs                            = { namespace = "external-secrets" }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

dependency "secret_stores" {
  config_path = "../secret-stores"

  mock_outputs                            = {}
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# Helm + Kubernetes providers authenticate to the cluster API by assuming PlatformDeployer (the cluster's
# access entry grants it admin). ARC runs ON the platform cluster, in-account, so this is the in-cluster
# exec path — same as every other platform add-on.
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
  create       = true
  cluster_name = dependency.eks.outputs.cluster_id
  region       = include.base.locals.region

  controller_chart_version = include.base.locals.helm_versions.arc_controller
  runner_set_chart_version = include.base.locals.helm_versions.arc_runner_set

  # Repo-scoped pool for privileged infra-apply (ADR-065). Workflows target it via `runs-on: platform-infra`.
  github_config_url     = "https://github.com/asanexample/platform"
  runner_scale_set_name = "platform-infra"
  min_runners           = 0
  max_runners           = 3

  # The custom toolchain image built by gha-runner-image.yml (platform/gha-runner). Bump this SHA + re-apply
  # to roll a new runner build (a /.tool-versions bump triggers the rebuild → new SHA here).
  runner_image = "829808296602.dkr.ecr.us-east-1.amazonaws.com/platform/gha-runner:9304c681c44b0c5c318c5072fe6bf3a313e99889"

  # GitHub App creds in Secrets Manager (JSON: appId, installationId, privateKey). Created out-of-band —
  # see docs/runbooks/arc-github-app.md.
  github_app_secret_name = "platform/gha-runner-controller/github-app"
  secret_store_name      = "aws-secrets-manager"

  # The runner role is granted permission to assume PlatformDeployer here, but the access stays INERT until
  # PlatformDeployer's trust admits the role (a separate, isolated change — the actual privilege grant).
  deployer_role_arn = include.base.locals.deployer_role_arn

  # Terragrunt assumes the state-backend role (root.hcl remote_state.role_arn) SEPARATELY from PlatformDeployer,
  # so a CI apply on the runner needs to assume it too. It lives in the management account and already trusts
  # the platform-account root unconditionally — granting the runner role AssumeRole on it is the only change.
  state_role_arn = "arn:aws:iam::${include.base.locals.account_ids["mgmt"]}:role/TerraformStateAccess"

  # The runner decrypts the SOPS config key (ADR-066) at config-eval time — it lives in the management account
  # (cross-account KMS needs the caller's IAM too). Scoped to the platform-sops key by alias condition, so this
  # is not a blanket decrypt on management's KMS keys.
  sops_key_arn_pattern = "arn:aws:kms:us-east-1:${include.base.locals.account_ids["mgmt"]}:key/*"
  sops_key_alias       = "alias/platform-sops"

  tags = include.base.locals.tags
}
