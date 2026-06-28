include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.keycloak
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

# External Secrets (the ExternalSecret CRD + operator) and secret-stores (the aws-secrets-manager
# ClusterSecretStore) sync the generated admin credential.
dependency "external_secrets" {
  config_path = "../external-secrets"

  mock_outputs                            = { namespace = "external-secrets", role_arn = "arn:aws:iam::000000000000:role/mock-ext-sec" }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

dependency "secret_stores" {
  config_path = "../secret-stores"

  mock_outputs                            = {}
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# CloudNativePG operator must exist before the Keycloak DB Cluster CR is applied.
dependency "cloudnative_pg" {
  config_path = "../cloudnative-pg"

  mock_outputs                            = {}
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# Foundational shared Gateway (ADR-053/059). Keycloak owns its HTTPRoute on it, so the endpoint is live BEFORE
# keycloak-config (which configures the realm through keycloak.aws.refplat.org). gateway has no app deps, so this
# does not create a cycle.
dependency "gateway" {
  config_path = "../gateway"

  mock_outputs = {
    gateway_name      = "platform-gateway"
    gateway_namespace = "default"
  }
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

  helm_chart_version = include.base.locals.helm_versions.keycloak

  # Deploy-only (B1): Keycloak runs alongside Dex at keycloak.aws.refplat.org. The realm, the Identity Center
  # SAML broker, OIDC clients, and group/role mappers (the access-model-as-code) land in B2; Dex still owns
  # sso.aws.refplat.org until the rebuild cutover. See ADR-053.
  hostname_url = "https://keycloak.aws.refplat.org"

  # Block the apply until Keycloak's pod is Ready (DB up + admin secret synced + serving) rather than returning
  # as soon as the Helm release is created. Makes "keycloak applied" mean "keycloak serving", so keycloak-config
  # (and its readiness gate) act on real readiness, and a stuck pod fails here with a clear error (ADR-059).
  helm_wait = true

  # Keycloak self-owns its HTTPRoute on the shared Gateway (ADR-059) — so the endpoint is up before keycloak-config.
  create_route      = true
  gateway_name      = dependency.gateway.outputs.gateway_name
  gateway_namespace = dependency.gateway.outputs.gateway_namespace

  # Teardown: drain the CNPG Cluster + PVC finalizers before the namespace delete (else it hangs Terminating).
  finalizer_clear_script = "${get_repo_root()}/scripts/k8s-finalizer-clear.sh"
  cluster_name           = dependency.eks.outputs.cluster_id
  region                 = include.base.locals.region
  deployer_role_arn      = include.base.locals.deployer_role_arn

  # Seal the bootstrap-admin secret (ADR-087): only these three roles may read platform/keycloak/admin —
  # the deployer (Terraform reads it on apply), the External Secrets Operator role (syncs it into the cluster),
  # and OrganizationAccountAccessRole (break-glass). Everyone else — incl. AdministratorAccess — is denied.
  admin_secret_reader_role_arns = [
    include.base.locals.deployer_role_arn,
    dependency.external_secrets.outputs.role_arn,
    "arn:aws:iam::${include.base.locals.account_id}:role/OrganizationAccountAccessRole",
  ]

  tags = include.base.locals.tags
}
