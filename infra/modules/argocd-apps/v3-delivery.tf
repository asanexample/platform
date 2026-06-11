# ===========================================================================================================
# v3 delivery (ADR-069 / L2b #384) — one ApplicationSet per Product.
#
# The git-files generator fans out over the product's Environment claims
# (gitops/environments/<team>/<product>/*.yaml in the platform repo) → ONE Application per Environment
# (decision c: per-Environment App; per-service digests live in the app overlay). The Application syncs the app
# repo's per-stage overlay (<repo>/k8s/overlays/<stage>) and injects ONLY namespace + host (static per env) —
# no image injection (the digest is whatever the overlay carries; the promotion/digest mechanism is P2, #377).
#
# ADDITIVE: coexists with the v2 `tenants` Applications above; enabled only when var.platform_repo_url is set.
# NOTE: ArgoCD ApplicationSet generators have NO offline test (they evaluate only inside a running ArgoCD), so
# this is a first draft that is cluster-verification-bound — unlike the crossplane-validated F1/L2a.
# ===========================================================================================================
locals {
  products = var.create && var.platform_repo_url != "" ? var.products : {}
}

resource "kubernetes_manifest" "product_appproject" {
  for_each = local.products

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "AppProject"
    metadata = {
      name      = "product-${each.key}"
      namespace = var.argocd_namespace
    }
    spec = {
      description = "v3 delivery for product ${each.value.team}/${each.value.product}"
      sourceRepos = compact([each.value.repo_url, var.platform_repo_url])
      destinations = [{
        server    = var.cluster_server
        namespace = "${each.value.team}-${each.value.product}-*" # the product's environments
      }]
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

resource "kubernetes_manifest" "product_appset" {
  for_each = local.products

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "ApplicationSet"
    metadata = {
      name      = "product-${each.key}"
      namespace = var.argocd_namespace
      labels = {
        "platform.refplat.org/team"    = each.value.team
        "platform.refplat.org/product" = each.value.product
      }
    }
    spec = {
      goTemplate        = true
      goTemplateOptions = ["missingkey=error"]
      # Fan out over the product's Environment claims in the platform repo → one param-set per env file.
      generators = [{
        git = {
          repoURL  = var.platform_repo_url
          revision = "HEAD"
          files    = [{ path = "gitops/environments/${each.value.team}/${each.value.product}/*.yaml" }]
        }
      }]
      template = {
        metadata = {
          # <team>-<product>-<stage> (customer envs disambiguated by the namespace below)
          name = "${each.value.team}-${each.value.product}-{{.spec.stage}}{{- if hasKey .spec \"customer\" }}-{{ .spec.customer }}{{- end }}"
          labels = {
            "platform.refplat.org/team"    = each.value.team
            "platform.refplat.org/product" = each.value.product
          }
        }
        spec = {
          project = "product-${each.key}"
          source = {
            repoURL        = each.value.repo_url
            targetRevision = "HEAD"
            path           = "k8s/overlays/{{ .spec.stage }}"
            kustomize = {
              # Inject the generated host (static per env). The digest is NOT injected — it lives in the synced
              # overlay (k8s/overlays/<stage>/kustomization.yaml images), promotion mechanism = P2 (#377).
              patches = var.preview_domain != "" ? [{
                target = { kind = "HTTPRoute" }
                patch = yamlencode([{
                  op    = "replace"
                  path  = "/spec/hostnames/0"
                  value = "{{ .spec.product }}-{{ .spec.team }}-{{ .spec.stage }}.${var.preview_domain}"
                }])
              }] : []
            }
          }
          destination = {
            server = var.cluster_server
            # Must EXACTLY match the Composition's namespace: <team>-<product>[-<customer>]-<stage>, with the
            # same truncate-and-hash on the 63-char limit (sha256 6-hex suffix), else the App targets a namespace
            # the Composition never created.
            namespace = "{{- $c := \"\" }}{{- if hasKey .spec \"customer\" }}{{ $c = printf \"-%s\" .spec.customer }}{{- end }}{{- $nsRaw := printf \"%s-%s%s-%s\" .spec.team .spec.product $c .spec.stage }}{{- if gt (len $nsRaw) 63 }}{{ printf \"%s-%s\" (substr 0 56 $nsRaw) (substr 0 6 (sha256sum $nsRaw)) }}{{- else }}{{ $nsRaw }}{{- end }}"
          }
          syncPolicy = {
            automated   = { selfHeal = true, prune = true }
            syncOptions = ["CreateNamespace=false"]
            retry       = local.sync_retry
          }
        }
      }
    }
  }

  depends_on = [kubernetes_manifest.product_appproject]
}
