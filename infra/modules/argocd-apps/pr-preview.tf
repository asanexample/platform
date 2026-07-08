# ===========================================================================================================
# PR preview (ADR-032) — one pullRequest-generator ApplicationSet per preview-enabled Product.
#
# Gated per-product on products[*].preview (spec.preview on the product's `dev` XEnvironment claim) AND on
# var.github_app_secret_name being set. Reuses the product-${key} AppProject already created in delivery.tf —
# same destination scope (<team>-<product>-* namespace, the same source repos) — no separate AppProject needed.
#
# Deploys INTO the existing `dev` namespace (not a new Environment per PR — provisioning a full Crossplane
# Environment per PR would be far too slow/heavy for something that appears on PR-opened and vanishes on
# PR-closed). Isolated from the stable dev deployment by kustomize namePrefix + commonLabels (ADR-032). Images
# are the PR's own head-SHA-tagged, cosign-signed build (preview.yml, already scaffolded) — no Release record,
# no digest promotion; previews intentionally bypass the gitops-Gate promotion ladder.
#
# The hostname pattern <product>-<team>-dev-pr-<N>.<preview_domain> is ALREADY unconditionally allow-listed by
# the Crossplane Composition's restrict-route-hostnames-<ns> Kyverno policy (a wildcard `-pr-*` entry) — no
# per-PR admission wiring needed here.
#
# Same caveat as delivery.tf: ArgoCD ApplicationSet generators have NO offline test (cluster-verification-bound).
# ===========================================================================================================
locals {
  preview_products = var.create && var.github_app_secret_name != "" ? {
    for k, v in var.products : k => v if v.preview
  } : {}

  # Namespace must exactly match the Composition's truncate-and-hash convention for <team>-<product>-dev
  # (same rule delivery.tf's Go-template applies at sync time from Release payload data) — computed here
  # instead since the PR generator's payload carries no product/environment data to template from.
  preview_namespace = { for k, v in local.preview_products :
    k => (
      length("${v.team}-${v.product}-dev") > 63
      ? "${substr("${v.team}-${v.product}-dev", 0, 56)}-${substr(sha256("${v.team}-${v.product}-dev"), 0, 6)}"
      : "${v.team}-${v.product}-dev"
    )
  }
}

resource "helm_release" "product_pr_preview" {
  for_each = local.preview_products

  name             = "product-${each.key}-pr-preview"
  namespace        = var.argocd_namespace
  chart            = "${path.module}/charts/applicationset-raw"
  create_namespace = false

  # Same passthrough-chart rationale as product_appset (delivery.tf): Terraform's kubernetes_manifest provider
  # can't represent ArgoCD's generator schema.
  values = [yamlencode({ manifest = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "ApplicationSet"
    metadata = {
      name      = "product-${each.key}-pr-preview"
      namespace = var.argocd_namespace
      labels = {
        "platform.refplat.org/team"    = each.value.team
        "platform.refplat.org/product" = each.value.product
      }
    }
    spec = {
      goTemplate        = true
      goTemplateOptions = ["missingkey=error"]
      generators = [{
        pullRequest = {
          # App-based auth reuses the SAME GitHub App ArgoCD already authenticates repo-creds with
          # (TD2-02b) — its githubAppID/githubAppInstallationID/githubAppPrivateKey Secret keys are
          # exactly what appSecretName expects. Requires the App's installation to carry Pull requests:
          # Read-only (manual, one-time, outside this Terraform — see ADR-032).
          github = {
            owner         = split("/", replace(each.value.repo_url, "https://github.com/", ""))[0]
            repo          = split("/", replace(each.value.repo_url, "https://github.com/", ""))[1]
            appSecretName = var.github_app_secret_name
          }
          requeueAfterSeconds = 60
        }
      }]
      template = {
        metadata = {
          name = "${each.value.team}-${each.value.product}-dev-pr-{{.number}}"
          labels = {
            "platform.refplat.org/team"    = each.value.team
            "platform.refplat.org/product" = each.value.product
          }
        }
        spec = {
          project = "product-${each.key}" # reuse the stable delivery AppProject, same destination scope
          source = {
            repoURL        = each.value.repo_url
            targetRevision = "{{.head_sha}}" # sync the PR's actual head commit, not just an image override
            path           = "k8s/overlays/dev"
            kustomize = {
              namePrefix = "pr-{{.number}}-"
              commonLabels = {
                "app.kubernetes.io/instance" = "pr-{{.number}}"
              }
              # One entry per service on the dev Environment claim (Terraform-known; the PR generator's own
              # payload has no product/service data to template this from, unlike delivery.tf's Release-driven
              # templatePatch). {{.head_sha}} matches the full SHA preview.yml already tags+signs+pushes.
              images = [for svc in each.value.services :
                "${var.ecr_registry}/team-${each.value.team}/${each.value.product}-${svc}:{{.head_sha}}"
              ]
              # Already Kyverno-allowed (restrict-route-hostnames-<ns>'s unconditional -pr-* wildcard entry) —
              # no per-PR admission wiring needed.
              patches = [{
                target = { kind = "HTTPRoute" }
                patch  = <<-EOT
                  - op: replace
                    path: /spec/hostnames/0
                    value: ${each.value.product}-${each.value.team}-dev-pr-{{.number}}.${var.preview_domain}
                EOT
              }]
            }
          }
          destination = {
            server    = var.cluster_server
            namespace = local.preview_namespace[each.key]
          }
          syncPolicy = {
            automated   = { selfHeal = true, prune = true }
            syncOptions = ["CreateNamespace=false", "RespectIgnoreDifferences=true", "ServerSideApply=true"]
            retry       = local.first_deploy_retry # previews are inherently first-deploy-shaped, never promoted
          }
          # Same Argo Rollouts (ADR-056) runtime-mutation exemptions as the stable delivery ApplicationSet
          # (delivery.tf) — every env workload is a Rollout, so selfHeal would otherwise fight the controller
          # here too, preview or not.
          ignoreDifferences = [
            { group = "", kind = "Service", jqPathExpressions = [".spec.selector"] },
            { group = "gateway.networking.k8s.io", kind = "HTTPRoute", jqPathExpressions = [".spec.rules[].backendRefs[].weight"] },
            # The default HPA (ADR-078 Phase 2) owns the Rollout replica count — ignore it so selfHeal doesn't fight it.
            { group = "argoproj.io", kind = "Rollout", jqPathExpressions = [".spec.replicas"] },
            { group = "argoproj.io", kind = "Rollout", managedFieldsManagers = ["rollouts-controller"] },
            { group = "gateway.networking.k8s.io", kind = "HTTPRoute", managedFieldsManagers = ["cilium-operator-generic"] },
          ]
        }
      }
    }
  }) })]

  depends_on = [kubernetes_manifest.product_appproject]
}
