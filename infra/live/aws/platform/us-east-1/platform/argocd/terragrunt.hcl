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
  # Git-native Team registry (ADR-063) — same gitops/teams/*.yaml the keycloak-config unit reads and ArgoCD
  # syncs. Only the team KEYS (metadata.name) matter here; they drive team-scoped ArgoCD RBAC (B3).
  teams_dir = "${get_repo_root()}/gitops/teams"
  teams = { for f in fileset(local.teams_dir, "*.yaml") :
    # Only the team KEYS matter here (team-scoped RBAC); the value is unused (`_cfg` below). Empty {} keeps the
    # map element type fixed, so a Team-spec field some teams have and others don't (platform's platformTrust,
    # ADR-081) can't make the types inconsistent.
    yamldecode(file("${local.teams_dir}/${f}")).metadata.name => {}
  }

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
      # v3 (ADR-067/069): a team's apps live in the per-Product AppProjects `product-<team>-<product>` (the
      # ApplicationSets create them), NOT a single team-named project — so scope to `product-${t}-*/*`. The glob
      # separator is `/`, so `product-${t}-*` matches every product of team `t` and `/*` matches its apps.
      for t, _cfg in local.teams : [
        "p, role:team-${t}, applications, get, product-${t}-*/*, allow",
        "p, role:team-${t}, applications, sync, product-${t}-*/*, allow",
        "p, role:team-${t}, logs, get, product-${t}-*/*, allow",
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

    # ArgoCD repo credentials via a GitHub App (TD2-02b) — ArgoCD mints + auto-refreshes installation tokens
    # itself, so there is no PAT to expire (the failure that silently broke repo sync, 2026-06-29). The App's
    # {appId, installationId, privateKey} live in Secrets Manager (platform/argocd/github-app, the standard
    # GitHub-App JSON shape); External Secrets projects them into the repo-creds secret, keeping the private key
    # OUT of terraform state. ArgoCD selects this credential by the repo-creds label + url prefix.
    resource "kubernetes_manifest" "argocd_repo_creds_github" {
      manifest = {
        apiVersion = "external-secrets.io/v1beta1"
        kind       = "ExternalSecret"
        metadata = {
          name      = "github-asanexample-app-creds"
          namespace = "argocd"
        }
        spec = {
          refreshInterval = "1h"
          secretStoreRef  = { name = "aws-secrets-manager", kind = "ClusterSecretStore" }
          target = {
            name           = "github-asanexample-app-creds"
            creationPolicy = "Owner"
            template = {
              metadata = { labels = { "argocd.argoproj.io/secret-type" = "repo-creds" } }
              data = {
                type                    = "git"
                url                     = "https://github.com/asanexample"
                githubAppID             = "{{ .appId }}"
                githubAppInstallationID = "{{ .installationId }}"
                githubAppPrivateKey     = "{{ .privateKey }}"
              }
            }
          }
          data = [
            { secretKey = "appId", remoteRef = { key = "platform/argocd/github-app", property = "appId" } },
            { secretKey = "installationId", remoteRef = { key = "platform/argocd/github-app", property = "installationId" } },
            { secretKey = "privateKey", remoteRef = { key = "platform/argocd/github-app", property = "privateKey" } },
          ]
        }
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
  region       = include.base.locals.region # AWS_REGION/regional-STS env for argocd-k8s-auth cross-account auth

  # AWS identity via EKS Pod Identity (ADR-047, #594) — no OIDC/IRSA inputs needed.

  helm_chart_version = include.base.locals.helm_versions.argocd
  helm_wait          = false # ArgoCD CRDs need time to register; sync-wave handles ordering

  high_availability = include.base.locals.high_availability # dev = single instance; prod = HA (cost_profile)

  # Faster GitOps loop: reconcile apps every 60s (default 180s, + ArgoCD's 60s jitter ≈ 3-4 min worst case →
  # ~1-2 min). With ArgoCD private (no GitHub→ArgoCD webhook reachable, ADR-010), this is the lever that
  # shortens "merge → live". Trivial load at our app count; the repo-server caches the git state.
  reconciliation_timeout = "60s"

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
    #
    # Only scalar/map-key paths belong in the kind-unscoped `.all` block. The containers[]/initContainers[]
    # array-notation paths below are deliberately NOT here — combined with RespectIgnoreDifferences=true
    # (delivery.tf) on a CRD without a registered Kubernetes scheme (argoproj.io/Rollout), ArgoCD's
    # normalizeTargetResources() falls back to an RFC7396 JSON Merge Patch, which cannot express a partial
    # array update and instead replaces the WHOLE array — silently reverting Rollout's `containers[].image`
    # to the stale live value while still reporting "successfully synced" (confirmed upstream:
    # argoproj/argo-cd#23283, #26588, fix argoproj/argo-cd#26924 still open as of 2026-07-14). Scalar/map
    # paths (this block) are provably safe: RFC7396 merges objects recursively and never touches unrelated
    # array fields. The array-notation rules are scoped to apps_Deployment/apps_StatefulSet below instead,
    # which have a registered scheme and use a proper strategic merge patch (no corruption risk).
    "resource.customizations.ignoreDifferences.all" = yamlencode({
      jqPathExpressions = [
        ".spec.template.spec.automountServiceAccountToken",
        ".spec.template.metadata.labels.team",
        ".spec.template.metadata.labels.\"app.kubernetes.io/name\"",
      ]
    })

    # The array-notation half of the Kyverno-tolerance rules above — deliberately excluded from Rollout
    # (argoproj.io CRD, unregistered scheme) to avoid the merge-patch corruption described above. Deployment
    # and StatefulSet are in the registered "apps" scheme, so they get a real strategic merge patch here and
    # can safely tolerate the same array-notation drift.
    "resource.customizations.ignoreDifferences.apps_Deployment" = yamlencode({
      jqPathExpressions = [
        ".spec.template.spec.containers[]?.securityContext.allowPrivilegeEscalation",
        ".spec.template.spec.containers[]?.securityContext.capabilities",
        ".spec.template.spec.containers[]?.securityContext.seccompProfile",
        ".spec.template.spec.initContainers[]?.securityContext.allowPrivilegeEscalation",
        ".spec.template.spec.initContainers[]?.securityContext.capabilities",
        ".spec.template.spec.initContainers[]?.securityContext.seccompProfile",
      ]
    })
    "resource.customizations.ignoreDifferences.apps_StatefulSet" = yamlencode({
      jqPathExpressions = [
        ".spec.template.spec.containers[]?.securityContext.allowPrivilegeEscalation",
        ".spec.template.spec.containers[]?.securityContext.capabilities",
        ".spec.template.spec.containers[]?.securityContext.seccompProfile",
        ".spec.template.spec.initContainers[]?.securityContext.allowPrivilegeEscalation",
        ".spec.template.spec.initContainers[]?.securityContext.capabilities",
        ".spec.template.spec.initContainers[]?.securityContext.seccompProfile",
      ]
    })

    # GitOps Environment claims (v3, ADR-067): Crossplane writes back into the XEnvironment XR — `spec.crossplane`
    # (compositionRef / compositionRevisionRef / resourceRefs) and the `composite.apiextensions.crossplane.io`
    # finalizer — which are NOT in the git claim YAML. Without this, selfHeal would treat them as drift and
    # strip them on sync, severing the composition binding and tearing the environment. Ignore the XR fields
    # Crossplane owns; the claim's own spec (team/product/stage/domains/services) still syncs from git.
    # (Renamed from the v2 _XTenant customization — XTenant was greenfield-renamed to XEnvironment at the v3
    # cutover, so the old key matched a kind that no longer exists, leaving XEnvironment drift unguarded.)
    "resource.customizations.ignoreDifferences.platform.refplat.org_XEnvironment" = yamlencode({
      jqPathExpressions = [".spec.crossplane"]
      jsonPointers      = ["/metadata/finalizers"]
    })
    # SSO via Keycloak OIDC (B3, ADR-053/059) — replaces the embedded Dex SAML connector. The browser flow uses
    # the confidential `argocd` client (clientSecret resolved from the synced Secret); the CLI uses the PUBLIC
    # `argocd-cli` client (PKCE, no secret) via cliClientID. `groups` claim carries team / platform-admins names.
    # (No `essential` on groups — an empty/absent claim must not block login while membership is unpopulated.)
    "oidc.config" = yamlencode({
      name            = "Keycloak"
      issuer          = dependency.keycloak_config.outputs.issuer
      clientID        = "argocd"
      clientSecret    = "$argocd-keycloak-oidc:client-secret"
      cliClientID     = "argocd-cli"
      requestedScopes = ["openid", "profile", "email", "groups"]
      # RP-initiated logout: logging out of ArgoCD also ends the Keycloak SSO session (ArgoCD substitutes
      # {{token}} with the id_token). Without this, ArgoCD logout only clears the local session, so Keycloak
      # silently re-authenticates the same user on the next login. post_logout_redirect_uri must be allowed by
      # the Keycloak `argocd` client (valid_post_logout_redirect_uris = argocd.aws.refplat.org/*).
      logoutURL = "${dependency.keycloak_config.outputs.issuer}/protocol/openid-connect/logout?post_logout_redirect_uri=https://argocd.aws.refplat.org/&id_token_hint={{token}}"
    })
  }

  # ArgoCD assumes these roles to deploy to remote clusters (cross-account)
  remote_cluster_role_arns = [
    dependency.preprod_iam_roles.outputs.role_arns["ArgoCD"], # Preprod account
  ]

  tags = include.base.locals.tags
}
