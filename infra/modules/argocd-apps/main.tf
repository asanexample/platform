locals {
  create = var.create

  tenants = local.create ? var.tenants : {}

  # Convention: "team-<name>" for namespace isolation, "vc-<name>" for vCluster; explicit namespace overrides both
  tenant_namespaces = { for k, v in local.tenants : k => coalesce(
    v.namespace,
    v.mode == "vcluster" ? "vc-${k}" : "team-${k}",
  ) }

  # Flatten nested team->app map into a flat "team-app" keyed map using merge(list...)
  applications = merge([
    for team_key, team in local.tenants : {
      for app_key, app in team.apps : "${team_key}-${app_key}" => {
        team_key    = team_key
        app_key     = app_key
        repo_url    = app.repo_url
        repo_path   = coalesce(app.repo_path, "k8s/preprod")
        repo_branch = coalesce(app.repo_branch, "main")
        namespace   = local.tenant_namespaces[team_key]
        preview     = coalesce(app.preview, false)
      }
    }
  ]...)

  preview_apps = { for k, v in local.applications : k => v if v.preview && var.github_org != "" }
}

# ---------------------------------------------------------------------------
# AppProject: one per team
# ---------------------------------------------------------------------------

resource "kubernetes_manifest" "app_project" {
  for_each = local.tenants

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "AppProject"
    metadata = {
      name      = each.key
      namespace = var.argocd_namespace
    }
    spec = {
      description = "Project for team ${each.key}"
      sourceRepos = distinct([for app in each.value.apps : app.repo_url])
      destinations = [{
        server    = var.cluster_server
        namespace = local.tenant_namespaces[each.key]
      }]
      # Tenant-deployable resource types; excludes cluster-scoped and privileged types
      namespaceResourceWhitelist = [
        { group = "", kind = "ConfigMap" },
        { group = "", kind = "Secret" },
        { group = "", kind = "Service" },
        { group = "", kind = "ServiceAccount" },
        { group = "apps", kind = "Deployment" },
        { group = "apps", kind = "StatefulSet" },
        { group = "batch", kind = "Job" },
        { group = "batch", kind = "CronJob" },
        { group = "gateway.networking.k8s.io", kind = "HTTPRoute" },
        { group = "external-secrets.io", kind = "ExternalSecret" },
      ]
    }
  }
}

# ---------------------------------------------------------------------------
# Application: one per app (main/stable)
# ---------------------------------------------------------------------------

resource "kubernetes_manifest" "application" {
  for_each = local.applications

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = each.key
      namespace = var.argocd_namespace
      labels = {
        "platform.refplat.org/tenant" = each.value.team_key
        "platform.refplat.org/app"    = each.value.app_key
      }
    }
    spec = {
      project = each.value.team_key
      source = {
        repoURL        = each.value.repo_url
        targetRevision = each.value.repo_branch
        path           = each.value.repo_path
        kustomize = {
          # Prevents label selector collision with preview (PR) deployments of the same app
          commonLabels = {
            "app.kubernetes.io/instance" = "stable"
          }
        }
      }
      destination = {
        server    = var.cluster_server
        namespace = each.value.namespace
      }
      syncPolicy = var.auto_sync ? {
        automated = {
          selfHeal = true
          prune    = true
        }
        syncOptions = ["CreateNamespace=false"] # Namespace lifecycle managed by the tenant module
        } : {
        automated   = null
        syncOptions = null
      }
    }
  }

  depends_on = [kubernetes_manifest.app_project]
}

# ---------------------------------------------------------------------------
# ApplicationSet: one per preview-enabled app (PR generator)
# ---------------------------------------------------------------------------

resource "kubernetes_manifest" "preview_appset" {
  for_each = local.preview_apps

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "ApplicationSet"
    metadata = {
      name      = "${each.key}-preview"
      namespace = var.argocd_namespace
      labels = {
        "platform.refplat.org/tenant" = each.value.team_key
        "platform.refplat.org/app"    = each.value.app_key
        "platform.refplat.org/type"   = "preview"
      }
    }
    spec = {
      goTemplate = true
      generators = [{
        pullRequest = {
          github = merge(
            {
              owner = var.github_org
              repo  = regex("[^/]+$", each.value.repo_url) # Extract repo name from URL
            },
            var.github_token_secret_name != "" ? {
              tokenRef = {
                secretName = var.github_token_secret_name
                key        = "token"
              }
            } : {}
          )
          requeueAfterSeconds = 60 # Poll GitHub for new/updated PRs every 60s
        }
      }]
      template = {
        metadata = {
          name = "${each.key}-pr-{{.number}}"
          labels = {
            "platform.refplat.org/tenant" = each.value.team_key
            "platform.refplat.org/app"    = each.value.app_key
            "platform.refplat.org/type"   = "preview"
          }
        }
        spec = {
          project = each.value.team_key
          source = {
            repoURL        = each.value.repo_url
            targetRevision = "{{.branch}}"
            path           = each.value.repo_path
            kustomize = {
              # namePrefix + commonLabels isolate preview resources from the stable deployment
              namePrefix = "pr-{{.number}}-"
              commonLabels = {
                "app.kubernetes.io/instance" = "pr-{{.number}}"
              }
              # Override image to the PR's head SHA; ECR repo follows "team-<team>/<app>" convention
              images = var.ecr_registry != "" ? [
                "${var.ecr_registry}/team-${each.value.team_key}/${each.value.app_key}:{{.head_sha}}"
              ] : []
              # Rewrite the first HTTPRoute hostname to a PR-specific subdomain
              patches = var.preview_domain != "" ? [
                {
                  target = { kind = "HTTPRoute" }
                  patch = yamlencode([
                    {
                      op    = "replace"
                      path  = "/spec/hostnames/0"
                      value = "${each.value.app_key}-pr-{{.number}}.${var.preview_domain}"
                    },
                  ])
                }
              ] : []
            }
          }
          destination = {
            server    = var.cluster_server
            namespace = each.value.namespace
          }
          syncPolicy = {
            automated = {
              selfHeal = true
              prune    = true
            }
            syncOptions = ["CreateNamespace=false"]
          }
        }
      }
    }
  }

  depends_on = [kubernetes_manifest.app_project]
}
