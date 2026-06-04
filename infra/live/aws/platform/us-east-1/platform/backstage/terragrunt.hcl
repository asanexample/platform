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

# OIDC (Phase 2.1): the ExternalSecret needs the operator + ClusterSecretStore, and the client secret
# (platform/backstage/oidc) is created by the dex module — so Backstage applies after all three.
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

dependency "dex" {
  config_path = "../dex"

  mock_outputs                            = { namespace = "dex" }
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
  image_tag = "1ad200cc87995e7eff3218dc075c5eaaf97737c7"

  # Split-horizon for OIDC SSO (Phase 2.1): the backend reaches Dex's issuer (sso.aws.refplat.org)
  # in-cluster via the Cilium gateway ClusterIP, not public DNS / the internal-NLB hairpin. The IP is
  # the `cilium-gateway-platform-gateway` Service ClusterIP (default ns) — stable for the Service's life;
  # if that Service is recreated, refresh this. TLS still validates (wildcard *.aws.refplat.org at the gateway).
  host_aliases = [{
    ip        = "172.20.184.24"
    hostnames = ["sso.aws.refplat.org"]
  }]

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

  # ArgoCD plugin (Phase 2.4b): read-only deployment view. The backend reaches our self-hosted ArgoCD
  # in-cluster over HTTP (server.insecure=true; the :443 Service port also maps to plaintext 8080, so https
  # would fail TLS). Read-only token (account `backstage`, role:readonly) synced from Secrets Manager
  # (platform/argocd/backstage-token) → ARGOCD_AUTH_TOKEN. Components link via `argocd/app-selector`.
  enable_argocd_plugin = true
  argocd_instances = [{
    name = "platform"
    url  = "http://argocd-server.argocd.svc"
  }]

  tags = include.base.locals.tags
}
