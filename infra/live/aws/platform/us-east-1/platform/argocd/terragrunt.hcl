include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.argocd
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

dependency "preprod_iam_roles" {
  config_path = "../../../../preprod/us-east-1/platform/iam-roles"

  mock_outputs = {
    role_arns = {
      ArgoCD = "arn:aws:iam::000000000000:role/ArgoCD"
    }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

generate "github_repo_creds" {
  path      = "github-repo-creds.tf"
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

    data "aws_secretsmanager_secret_version" "github_pat" {
      secret_id = "platform/github/argocd-pat"
    }

    resource "kubernetes_secret_v1" "argocd_repo_creds_github" {
      metadata {
        name      = "github-asanexample-creds"
        namespace = "argocd"
        labels = {
          "argocd.argoproj.io/secret-type" = "repo-creds"
        }
      }

      data = {
        type     = "git"
        url      = "https://github.com/asanexample"
        username = "x-access-token"
        password = data.aws_secretsmanager_secret_version.github_pat.secret_string
      }

      depends_on = [helm_release.argocd]
    }
  EOF
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
  create       = true
  cluster_name = dependency.eks.outputs.cluster_id

  oidc_provider_arn = dependency.eks.outputs.oidc_provider_arn
  oidc_provider_url = dependency.eks.outputs.oidc_provider_url

  helm_chart_version = include.base.locals.helm_versions.argocd
  helm_wait          = false # ArgoCD CRDs need time to register; sync-wave handles ordering

  high_availability = false # Single instance — sufficient for non-production platform cluster

  dex_enabled = true
  rbac_scopes = "[groups]"

  # Group UUIDs are IAM Identity Center group IDs (Admins, Developers, ReadOnly)
  rbac_policy_csv = <<-CSV
    p, role:org-admin, applications, *, */*, allow
    p, role:org-admin, clusters, get, *, allow
    p, role:org-admin, repositories, *, *, allow
    p, role:org-admin, logs, get, *, allow
    p, role:org-admin, exec, create, */*, allow
    g, org-admin, role:org-admin
    p, role:developer, applications, get, */*, allow
    p, role:developer, applications, sync, */*, allow
    p, role:developer, logs, get, *, allow
    g, a4b884e8-f021-7042-5f38-65d571afff7c, role:admin
    g, a4c85418-d071-7051-9bee-c5a90ee7963e, role:developer
    g, c4b87428-8051-7073-9af0-a31f4b94daac, role:readonly
  CSV

  argocd_cm_extra = {
    "url" = "https://argocd.aws.refplat.org"

    # Kyverno Phase 2 (#73): the policy engine mutates these fields at admission (safe-default
    # securityContext / automountServiceAccountToken / identity labels). Tell ArgoCD to ignore the
    # mutated sub-fields so selfHeal doesn't fight Kyverno (which would thrash). Scoped to only the
    # mutated paths — app-controlled fields (runAsNonRoot, etc.) still sync. The admission webhook
    # (disallow-privilege-escalation / require-seccomp) is what actually enforces these, so ignoring
    # the ArgoCD diff is safe. See docs/architecture/kyverno-policy-catalog.md.
    "resource.customizations.ignoreDifferences.all" = yamlencode({
      jqPathExpressions = [
        ".spec.template.spec.automountServiceAccountToken",
        ".spec.template.spec.containers[]?.securityContext.allowPrivilegeEscalation",
        ".spec.template.spec.containers[]?.securityContext.capabilities",
        ".spec.template.spec.containers[]?.securityContext.seccompProfile",
        ".spec.template.spec.initContainers[]?.securityContext.allowPrivilegeEscalation",
        ".spec.template.spec.initContainers[]?.securityContext.capabilities",
        ".spec.template.spec.initContainers[]?.securityContext.seccompProfile",
        ".spec.template.metadata.labels.team",
        ".spec.template.metadata.labels.\"app.kubernetes.io/name\"",
      ]
    })
    "dex.config" = yamlencode({
      connectors = [{
        type = "saml"
        id   = "aws-sso"
        name = "AWS SSO"
        config = {
          ssoURL             = include.base.locals.all_vars.argocd_sso_url
          caData             = include.base.locals.all_vars.argocd_sso_ca_data
          redirectURI        = "https://argocd.aws.refplat.org/api/dex/callback"
          entityIssuer       = "https://argocd.aws.refplat.org/api/dex/callback"
          nameIDPolicyFormat = "emailAddress"
          usernameAttr       = "email"
          emailAttr          = "email"
          groupsAttr         = "groups"
        }
      }]
    })
  }

  # ArgoCD assumes these roles to deploy to remote clusters (cross-account)
  remote_cluster_role_arns = [
    dependency.preprod_iam_roles.outputs.role_arns["ArgoCD"], # Preprod account
  ]

  tags = include.base.locals.tags
}
