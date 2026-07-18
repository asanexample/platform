include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.activation_operator
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

# Ordering: the operator watches WorkforceRole/Person (cap + eligibility) — those CRDs ship with the
# crossplane governance-registry chart (enable_governance_registry), so crossplane must apply first or the
# operator's cache fails to start.
dependency "crossplane" {
  config_path = "../crossplane"

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

  cluster_name          = dependency.eks.outputs.cluster_id
  region                = include.base.locals.region
  management_account_id = include.base.locals.account_ids["mgmt"]

  # Digest-pinned operator image (built + cosign-signed by operator-image.yml → platform ECR). Bump this
  # digest to the build output and re-apply, like the ARC runner_image (ADR-071 digest-pin). Current:
  # the extend renew-annotation-key fix (PR #1024).
  image = "829808296602.dkr.ecr.us-east-1.amazonaws.com/platform/activation-operator@sha256:1b314a2e0940b8ecdbf7f3e57ae76c9e2a5c45e7ce6682ccbd7d9f6bae72e93e"

  # Unified telemetry → the cluster otel-collector (traces+metrics OTLP). Empty would disable export.
  otel_endpoint = "http://otel-collector.observability.svc:4317"

  # Durable governance audit (ADR-088 §3.6): project the ADR-084 directory Postgres connection from Secrets
  # Manager into the `activation-audit-db` Secret, which the operator reads as AUDIT_DB_DSN. The directory DB's
  # CiliumNetworkPolicy admits this namespace (platform-directory.extra_consumer_namespaces).
  audit_db_secret    = "activation-audit-db"
  audit_db_secret_id = "platform/activation-operator/audit-writer-db"

  tags = include.base.locals.tags
}
