include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.tenant_claims
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

# Ordering only: the XTenant XRD + Composition (crossplane unit) must exist before a claim is applied.
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

inputs = {
  create = true

  # Tenant claims (BACK stack P3). Each entry is an XTenant spec, rendered verbatim by the tenant-claims
  # chart and provisioned by the federated Composition (ADR-046/048). A team here MUST be marked
  # `migrated = true` in teams.hcl so its Terragrunt-provisioned infra is withdrawn (no "half in each").
  tenants = {
    # team-alpha — migrated off teams.hcl (#174). S3 dropped (demo); app-alpha needs no other AWS, so
    # policyStatements is empty (Pod-team-alpha role + Pod Identity association still created, inert).
    # resourceQuota omitted → XRD defaults match the tenant module; developerAccess defaults to enabled.
    alpha = {
      team      = "alpha"
      hostnames = ["demo.preprod.aws.refplat.org"]
      apps = {
        demo = {
          repoPath = "k8s/preprod"
          preview  = true
        }
      }
      aws = {
        serviceAccount   = "app-alpha"
        policyStatements = []
      }
    }
  }

  tags = include.base.locals.tags
}
