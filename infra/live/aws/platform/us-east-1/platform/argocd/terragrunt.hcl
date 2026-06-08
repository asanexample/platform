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

locals {
  # Canonical Team registry (same source as keycloak-config + crossplane) — drives team-scoped ArgoCD RBAC (B3).
  teams = read_terragrunt_config(find_in_parent_folders("aws/_teams.hcl")).locals.teams

  # Team-scoped RBAC, generated from the registry (ADR-053). Each team group → a role scoped to its AppProject
  # (project name == team key): get/sync/logs only — the operate posture; NO create/delete/exec, NO cluster/repo,
  # NO `default` project. platform-admins → org-admin. Default policy is deny (rbac_default_policy = ""). The
  # `backstage` local account stays read-only (its ArgoCD plugin token). Named claims replace the old IdC UUIDs.
  argocd_rbac_csv = join("\n", concat([
    "p, role:org-admin, applications, *, */*, allow",
    "p, role:org-admin, clusters, get, *, allow",
    "p, role:org-admin, repositories, *, *, allow",
    "p, role:org-admin, logs, get, *, allow",
    "p, role:org-admin, exec, create, */*, allow",
    "g, platform-admins, role:org-admin",
    ], flatten([
      for t, _cfg in local.teams : [
        "p, role:team-${t}, applications, get, ${t}/*, allow",
        "p, role:team-${t}, applications, sync, ${t}/*, allow",
        "p, role:team-${t}, logs, get, ${t}/*, allow",
        "g, ${t}, role:team-${t}",
      ]
    ]), [
    "g, backstage, role:readonly",
  ]))
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

# B3 (ADR-053/059): ArgoCD SSO now brokers through Keycloak, so it runs AFTER keycloak-config. This single
# dependency also transitively orders argocd after the whole Keycloak chain (keycloak → cnpg/secret-stores/
# external-secrets), guaranteeing the ESO CRD + ClusterSecretStore exist for the OIDC ExternalSecret and that the
# argocd OIDC client secret is already in Secrets Manager. Provides the realm issuer + the SM secret name.
dependency "keycloak_config" {
  config_path = "../keycloak-config"

  mock_outputs = {
    issuer              = "https://keycloak.aws.refplat.org/realms/platform"
    client_secret_names = { argocd = "platform/keycloak/argocd-oidc" }
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

  # Prometheus metrics + ServiceMonitors for the observability hub dashboards (#102 P1).
  metrics_enabled = true

  # SSO is now Keycloak OIDC (B3, ADR-053/059) — ArgoCD's embedded Dex is disabled (Keycloak brokers up to IdC).
  dex_enabled = false
  rbac_scopes = "[groups]" # named team / platform-admins group claims (not the roles claim, not UUIDs)

  # Default-deny: only explicitly-granted groups get any access (no platform-wide readonly). Team isolation +
  # platform-admins → org-admin, generated from the canonical registry. See locals.argocd_rbac_csv.
  rbac_default_policy = ""
  rbac_policy_csv     = local.argocd_rbac_csv

  # OIDC client secret (Keycloak `argocd` confidential client) → synced from Secrets Manager into a part-of:argocd
  # Secret that argocd-cm references as $argocd-keycloak-oidc:client-secret.
  oidc_external_secret_enabled = true
  oidc_secret_manager_key      = dependency.keycloak_config.outputs.client_secret_names["argocd"]

  argocd_cm_extra = {
    "url" = "https://argocd.aws.refplat.org"

    # Read-only, token-only local account for the Backstage ArgoCD plugin (2.4b). `apiKey` lets it hold an
    # API token but not log in interactively; RBAC binds it to the built-in role:readonly (see rbac_policy_csv,
    # `g, backstage, role:readonly`). The token is minted out-of-band + stored in Secrets Manager
    # (platform/argocd/backstage-token) — see docs/runbooks/backstage-argocd.md. ADR-051: read-only, never admin.
    "accounts.backstage" = "apiKey"

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

    # GitOps tenant claims (BACK stack Phase 1): Crossplane writes back into the XTenant XR — `spec.crossplane`
    # (compositionRef / compositionRevisionRef / resourceRefs) and the `composite.apiextensions.crossplane.io`
    # finalizer — which are NOT in the git claim YAML. Without this, selfHeal would treat them as drift and
    # strip them on sync, severing the composition binding and tearing the tenant. Ignore the XR fields
    # Crossplane owns; the claim's own spec (team/hostnames/apps/aws) still syncs from git.
    "resource.customizations.ignoreDifferences.platform.refplat.org_XTenant" = yamlencode({
      jqPathExpressions = [".spec.crossplane"]
      jsonPointers      = ["/metadata/finalizers"]
    })
    # SSO via Keycloak OIDC (B3, ADR-053/059) — replaces the embedded Dex SAML connector. The browser flow uses
    # the confidential `argocd` client (clientSecret resolved from the synced Secret); the CLI uses the PUBLIC
    # `argocd-cli` client (PKCE, no secret) via cliClientID. `groups` claim carries team / platform-admins names.
    # (No `essential` on groups — an empty/absent claim must not block login while membership is unpopulated.)
    "oidc.config" = yamlencode({
      name         = "Keycloak"
      issuer       = dependency.keycloak_config.outputs.issuer
      clientID     = "argocd"
      clientSecret = "$argocd-keycloak-oidc:client-secret"
      cliClientID  = "argocd-cli"
      # NO "groups" scope: Keycloak has no registered `groups` client scope (requesting it → invalid_scope).
      # Our keycloak-config emits the `groups` claim via a per-CLIENT protocol mapper, so it's in every token
      # regardless of requested scopes — ArgoCD reads it for RBAC (rbac_scopes = "[groups]") without asking for
      # a scope. (To let apps request a first-class `groups` scope canonically, add a Keycloak groups client
      # scope in keycloak-config instead — tracked as a follow-up.)
      requestedScopes = ["openid", "profile", "email"]
    })
  }

  # ArgoCD assumes these roles to deploy to remote clusters (cross-account)
  remote_cluster_role_arns = [
    dependency.preprod_iam_roles.outputs.role_arns["ArgoCD"], # Preprod account
  ]

  tags = include.base.locals.tags
}
