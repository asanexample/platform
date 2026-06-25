# triage-copilot agent identity (ADR-080): a read-only IAM role (bedrock:InvokeModel
# only) + an EKS Pod Identity association. The agent WORKLOAD (namespace, ServiceAccount,
# Deployment, RBAC) is delivered by ArgoCD from the app repo (asanexample/triage-copilot),
# NOT here — this unit provisions ONLY the AWS identity. Depends on eks for the cluster name.

include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.triage_copilot_identity
}

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_id = "mock-cluster"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

inputs = {
  create       = true
  cluster_name = dependency.eks.outputs.cluster_id

  aws_account_id = include.base.locals.account_id

  # The model the agent invokes: a cross-region inference profile + its foundation model.
  inference_profile_id = "us.anthropic.claude-sonnet-4-6"
  foundation_model_id  = "anthropic.claude-sonnet-4-6*"

  tags = include.base.locals.tags
}
