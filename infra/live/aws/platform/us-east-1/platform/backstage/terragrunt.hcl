include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.backstage
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

# Orders Backstage after the CloudNativePG operator (the in-cluster DB Cluster CR needs the CRDs + the
# reconciling controller to exist).
dependency "cloudnative_pg" {
  config_path = "../cloudnative-pg"

  mock_outputs = {
    namespace = "cnpg-system"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# OIDC: the ExternalSecret needs the operator + ClusterSecretStore, and the Keycloak `backstage` client
# secret (platform/keycloak/backstage-oidc) is created by keycloak-config — so Backstage applies after all.
dependency "external_secrets" {
  config_path = "../external-secrets"

  mock_outputs                            = { namespace = "external-secrets" }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# Ordering: Backstage's OIDC client secret (platform/keycloak/backstage-oidc) is provisioned by keycloak-config,
# so Backstage must apply after it (the ExternalSecret would otherwise have nothing to sync).
dependency "keycloak_config" {
  config_path = "../keycloak-config"

  mock_outputs                            = { issuer = "https://keycloak.aws.refplat.org" }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

dependency "secret_stores" {
  config_path = "../secret-stores"

  mock_outputs                            = {}
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# Cross-environment dependencies (Phase 2.4a Kubernetes plugin): the portal reads the preprod workload
# cluster read-only. Endpoint/CA come from the preprod eks unit; the cross-account read-only role ARN that
# this pod assumes comes from the preprod iam-roles unit (the `Backstage` role).
dependency "preprod_eks" {
  config_path = "../../../../preprod/us-east-1/platform/eks"

  mock_outputs = {
    cluster_id                    = "mock-preprod-cluster"
    cluster_endpoint              = "https://mock-preprod-endpoint"
    cluster_certificate_authority = "bW9jaw=="
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

dependency "preprod_iam_roles" {
  config_path = "../../../../preprod/us-east-1/platform/iam-roles"

  mock_outputs = {
    role_arns = { Backstage = "arn:aws:iam::000000000000:role/Backstage" }
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

  helm_chart_version = include.base.locals.helm_versions.backstage

  # The signed image built by the asanexample/backstage repo CI (platform/backstage). Bump this SHA +
  # re-apply to roll out a new portal build (Terragrunt-deployed; not GitOps like the tenant apps).
  # This SHA (asanexample/backstage#37) completes the L2c v3 frontend: projection (#35) + #285 card re-point (#36)
  # + the kind:Environment relation processor (ownedBy/partOf) + team-tenants → Environments. BACKWARD-COMPATIBLE +
  # INERT: platformProjection.mode defaults to 'v2', so the live catalog behaves identically until the cutover sets
  # mode='v3' (a pure config flip — all L2c frontend code is now in this image). (Prior 15c5a0fc = #36; 81e4b544 = #35.)
  image_tag = "4fbd38d36fe9821dd3f63c8d31493360cd8b8b67"

  # v3 cutover (ADR-067): flip the platform-projection catalog mode to v3 (Product=System, Environment=custom
  # kind). Injected as an appConfig layer that overrides the image's default 'v2' — no new image needed (the
  # L2c frontend already ships in image_tag above).
  projection_mode = "v3"

  # Split-horizon for OIDC: pin keycloak.aws.refplat.org to the gateway's ClusterIP so the backend hits the
  # gateway Envoy directly (the public-name → internal-NLB hairpin is flaky). The ClusterIP is resolved
  # DYNAMICALLY by the module from the gateway Service — no hardcoded IP — so it self-corrects on apply.
  oidc_gateway_alias_host = "keycloak.aws.refplat.org"

  # Phase 2.0: in-cluster CloudNativePG (dev). Flip to mode = "rds" (+ rds_host/rds_secret_name) for prod.
  database = {
    mode         = "in-cluster"
    instances    = 1
    storage_size = "5Gi"
  }

  # Kubernetes plugin (Phase 2.4a): read-only live view of this (platform) cluster via the pod's EKS Pod
  # Identity reader role, and of the preprod workload cluster by assuming the cross-account read-only
  # `Backstage` role there. View-only (AmazonEKSViewPolicy excludes Secrets); ADR-051 §live-plugins.
  enable_kubernetes_plugin = true
  cluster_name             = dependency.eks.outputs.cluster_id
  remote_cluster_role_arns = [dependency.preprod_iam_roles.outputs.role_arns["Backstage"]]
  # NB: `name` MUST be the real EKS cluster name — Backstage's AWS auth uses it as the EKS token's
  # `x-k8s-aws-id` (AwsIamStrategy), so a display name like "preprod" yields a token for the wrong cluster
  # and the API returns 401. Use the eks units' cluster_id (platform-use1-eks / preprod-use1-eks).
  kubernetes_clusters = [
    {
      name    = dependency.eks.outputs.cluster_id
      url     = dependency.eks.outputs.cluster_endpoint
      ca_data = dependency.eks.outputs.cluster_certificate_authority
    },
    {
      name        = dependency.preprod_eks.outputs.cluster_id
      url         = dependency.preprod_eks.outputs.cluster_endpoint
      ca_data     = dependency.preprod_eks.outputs.cluster_certificate_authority
      assume_role = dependency.preprod_iam_roles.outputs.role_arns["Backstage"]
    },
  ]

  # Scaffolder (BACK Phase 3, ADR-062): inject the separate GitHub WRITE App credential
  # (platform/backstage/scaffolder-github-app — Contents+PRs read/write, installed on asanexample/platform
  # only) as SCAFFOLDER_GITHUB_APP_ID/_PRIVATE_KEY. The image's app-config wires the App + the /create page +
  # the platform-repo template location (scaffolder/templates/). Template execution is admin-only (the #197
  # permission policy). See docs/runbooks/backstage-scaffolder-github-app.md.
  enable_scaffolder = true

  # ArgoCD plugin (Phase 2.4b): read-only deployment view. The backend reaches our self-hosted ArgoCD
  # in-cluster over HTTP (server.insecure=true; the :443 Service port also maps to plaintext 8080, so https
  # would fail TLS). Read-only token (account `backstage`, role:readonly) synced from Secrets Manager
  # (platform/argocd/backstage-token) → ARGOCD_AUTH_TOKEN. Components link via `argocd/app-selector`.
  enable_argocd_plugin = true
  argocd_instances = [{
    name         = "platform"
    url          = "http://argocd-server.argocd.svc" # backend → in-cluster API (HTTP, insecure)
    frontend_url = "https://argocd.aws.refplat.org"  # browser → "open in ArgoCD" links (gateway, public)
  }]

  # Destroy-time namespace drain auth (scripts/k8s-finalizer-clear.sh) — see the module's namespace_drain.
  region                 = include.base.locals.region
  deployer_role_arn      = include.base.locals.deployer_role_arn
  finalizer_clear_script = "${get_repo_root()}/scripts/k8s-finalizer-clear.sh"

  tags = include.base.locals.tags
}
