# ===========================================================================================================
# delivery (ADR-069 / L2b #384; release-keyed #377) — one ApplicationSet per Product.
#
# The git-files generator fans out over the product's Release records (gitops/releases/<team>/<product>/*.yaml
# in the platform repo) → ONE Application per Release (= per Environment that has a deployed digest). The
# Application syncs the app repo's per-stage overlay (<repo>/k8s/overlays/<stage>) and injects namespace + host
# (derived from the Release's spec.environmentRef) plus the per-Service signed digest as a kustomize image
# override (ADR-071). Keying on the Release — not the Environment — is what lets a Product deliver to MORE THAN
# ONE stage; the old per-Environment merge generator collided on a null merge key (#377).
#
# ADDITIVE: coexists with the v2 `tenants` Applications above; enabled only when var.platform_repo_url is set.
# NOTE: ArgoCD ApplicationSet generators have NO offline test (they evaluate only inside a running ArgoCD), so
# this is a first draft that is cluster-verification-bound — unlike the crossplane-validated F1/L2a.
# ===========================================================================================================
locals {
  # Agent Products deliver to the HUB via the platform-agent ApplicationSet (agents.tf, ADR-082), NOT to preprod
  # via this per-Product appset — so exclude them here, else the agent would be double-delivered (and to a
  # tenant namespace it no longer has). Keyed by the gitops/products registry key <team>-<product>.
  agent_product_keys = toset([for a in var.agents : a.product_key])
  products = var.create && var.platform_repo_url != "" ? {
    for k, v in var.products : k => v if !contains(local.agent_product_keys, k)
  } : {}
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
      description = "delivery for product ${each.value.team}/${each.value.product}"
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
        # Argo Rollouts (ADR-056): every workload is a Rollout; AnalysisTemplate/AnalysisRun back the metric
        # gates. Without these in the whitelist ArgoCD refuses to sync the Rollout ("resource not permitted in
        # project"). Deployment/StatefulSet are kept for the migration window.
        { group = "argoproj.io", kind = "Rollout" },
        { group = "argoproj.io", kind = "AnalysisTemplate" },
        { group = "argoproj.io", kind = "AnalysisRun" },
        { group = "batch", kind = "Job" },
        { group = "batch", kind = "CronJob" },
        { group = "gateway.networking.k8s.io", kind = "HTTPRoute" },
        { group = "external-secrets.io", kind = "ExternalSecret" },
        # A service declares who may call it: tenants author their own east-west allow-rules (and, ADR-057
        # Phase 2, mutual-auth CiliumNetworkPolicies). Namespaced + ADDITIVE — a tenant can only open ingress
        # to its OWN pods; it cannot remove the Composition's default-deny or the IMDS egressDeny (a Cilium
        # egressDeny takes strict precedence over every allow), and it cannot affect another namespace.
        { group = "networking.k8s.io", kind = "NetworkPolicy" },
        { group = "cilium.io", kind = "CiliumNetworkPolicy" },
        # CNPG database (ADR-099 / ADR-081 amendment): a platform-trust service co-locates its Postgres as a
        # postgresql.cnpg.io Cluster (the CNPG operator provisions the rest — Pods/PVCs/Secrets — which ArgoCD
        # does not manage). Namespaced + additive; a TENANT product could declare one too, but its CNPG pods are
        # still rejected by the environment image floor (only a platform-trust namespace is exempt, ADR-081
        # amendment), so the kind is inert outside a platform-trust Environment.
        { group = "postgresql.cnpg.io", kind = "Cluster" },
      ]
    }
  }
}

resource "helm_release" "product_appset" {
  for_each = local.products

  name             = "product-${each.key}"
  namespace        = var.argocd_namespace
  chart            = "${path.module}/charts/applicationset-raw"
  create_namespace = false

  # ADR-071 (B-via-Helm): the ApplicationSet uses a recursive `merge` generator, which Terraform's
  # kubernetes_manifest provider cannot represent (it crashes resolving the self-referential generators schema).
  # Build the manifest as data and apply it via the passthrough chart — Helm emits it verbatim (no recursive type
  # validation; ArgoCD's {{ }} survive because Helm does not re-parse substituted values).
  values = [yamlencode({ manifest = yamlencode({
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
      # Fan out over the product's Release records (ADR-071, #377) — ONE Application per Release. Each
      # gitops/releases/<t>/<p>/<stage>[-<customer>].yaml carries the deployed digest(s) for one Environment; the
      # template derives stage (and optional customer) from spec.environmentRef (= <team>-<product>[-<customer>]-
      # <stage>, the sibling Environment's name) and team/product come from the Terraform loop. A SINGLE git-files
      # generator — the prior `merge` keyed on `path.basenameNormalized`, which is null under goTemplate (every
      # field nests), so a 2nd Environment for the same Product collided on the {null} key and broke the WHOLE
      # ApplicationSet (#377 — no Product could deliver to >1 stage). Release-keyed has no merge key to collide.
      # An Environment with no Release yet generates NO Application (no doomed :placeholder sync); its first
      # promote writes the Release and the App appears.
      generators = [{
        git = {
          repoURL  = var.platform_repo_url
          revision = "HEAD"
          files    = [{ path = "gitops/releases/${each.value.team}/${each.value.product}/*.yaml" }]
        }
      }]
      template = {
        metadata = {
          # <team>-<product>-<stage>[-<customer>], derived from the Release's spec.environmentRef
          # (= <team>-<product>[-<customer>]-<stage>). stage is the FINAL dash-segment — allowedStages is a
          # closed CRD enum (dev/test/uat/staging/prod), none with a dash — and customer is whatever precedes it.
          name = "${each.value.team}-${each.value.product}-{{- $rest := trimPrefix \"${each.value.team}-${each.value.product}-\" .spec.environmentRef }}{{- $parts := splitList \"-\" $rest }}{{ last $parts }}{{- if gt (len $parts) 1 }}-{{ join \"-\" (initial $parts) }}{{- end }}"
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
            path           = "k8s/overlays/{{ splitList \"-\" .spec.environmentRef | last }}"
            kustomize = {
              # Inject the generated host (static per env). The per-Service digest is injected by templatePatch
              # below (ADR-071) from this Release record — the overlay ships `:placeholder`. stage = the final
              # dash-segment of spec.environmentRef (allowedStages is a closed CRD enum, no dashes). The patch is
              # a HEREDOC (not yamlencode) so the `splitList "-"` quotes survive as a literal block scalar — a
              # yamlencoded patch escapes them to `\"`, which ArgoCD's goTemplate cannot parse.
              patches = var.preview_domain != "" ? [{
                target = { kind = "HTTPRoute" }
                patch  = <<-EOT
                  - op: replace
                    path: /spec/hostnames/0
                    value: ${each.value.product}-${each.value.team}-{{ splitList "-" .spec.environmentRef | last }}.${var.preview_domain}
                EOT
              }] : []
            }
          }
          destination = {
            server = var.cluster_server
            # Must EXACTLY match the Composition's namespace: <team>-<product>[-<customer>]-<stage>. That string
            # IS the Release's spec.environmentRef (the Environment's metadata.name), so use it verbatim with the
            # same truncate-and-hash on the 63-char limit (sha256 6-hex suffix) the Composition applies, else the
            # App targets a namespace the Composition never created.
            namespace = "{{- $nsRaw := .spec.environmentRef }}{{- if gt (len $nsRaw) 63 }}{{ printf \"%s-%s\" (substr 0 56 $nsRaw) (substr 0 6 (sha256sum $nsRaw)) }}{{- else }}{{ $nsRaw }}{{- end }}"
          }
          syncPolicy = {
            automated = { selfHeal = true, prune = true }
            # ServerSideApply (#894): an Argo Rollout carries TWO field managers on its spec — argocd-controller
            # AND rollouts-controller (the controller mutates spec at runtime). ArgoCD's DEFAULT client-side apply
            # computes its patch from the `kubectl.kubernetes.io/last-applied-configuration` annotation via a 3-way
            # merge; with a second manager also writing spec, that merge can resolve a committed `spec.template`
            # change to a NO-OP — the apply logs `rollout … unchanged`, no new ReplicaSet rolls, and the app stays
            # OutOfSync (only a manual `kubectl patch` lands it). Server-side apply uses real managedFields
            # field-ownership instead of the annotation, so argocd-controller's owned spec.template is applied
            # correctly alongside the rollouts-controller's fields. The registry-sync apps below already run with
            # SSA on this cluster (ArgoCD v3.4.x).
            #
            # RespectIgnoreDifferences keeps a SYNC (selfHeal or manual) from overwriting the ignoreDifferences
            # fields below — without it, ignoreDifferences only hides them from the diff, and a sync triggered by
            # any OTHER change still stomps the plugin's live HTTPRoute weights / the rollout's Service selector.
            syncOptions = ["CreateNamespace=false", "RespectIgnoreDifferences=true", "ServerSideApply=true"]
            # Fail-fast (not the 45-min sync_retry): a new Environment's first deploy syncs a `:placeholder`
            # overlay until the app's CI pins the signed digest in a follow-up commit; a short retry lets the
            # doomed pre-pin sync give up so selfHeal picks up the pin commit (revision change) without a manual
            # terminate-op. The registry-sync app below keeps the long sync_retry.
            retry = local.first_deploy_retry
          }
          # Argo Rollouts (ADR-056) hands runtime control of two fields to the rollouts controller during a
          # progressive deploy; without these, `selfHeal` reverts them every reconcile and fights the rollout:
          #   • Service .spec.selector — the controller injects `rollouts-pod-template-hash` so the stable/canary
          #     (and blueGreen active/preview) Services target the right revision's pods.
          #   • HTTPRoute backendRef weights — the Gateway-API trafficrouter plugin shifts them per canary step.
          # Harmless for non-Rollout / non-canary apps (no such field to ignore). git stays the source of truth
          # for everything else, including the at-rest weights (the controller restores 100/0 between rollouts).
          ignoreDifferences = [
            { group = "", kind = "Service", jqPathExpressions = [".spec.selector"] },
            { group = "gateway.networking.k8s.io", kind = "HTTPRoute", jqPathExpressions = [".spec.rules[].backendRefs[].weight"] },
            # The default HPA (ADR-078 Phase 2) owns the Rollout's replica count at runtime — ignore it so
            # selfHeal doesn't revert the HPA's scaling to the manifest's initial value (thrash). The
            # manifest's replicas is only the initial; the HPA's min/max govern thereafter.
            { group = "argoproj.io", kind = "Rollout", jqPathExpressions = [".spec.replicas"] },
            # #894: under ServerSideApply, foreign controllers co-own these via Update (rollouts-controller on the
            # Rollout, cilium-operator-generic on the HTTPRoute), producing an empty-diff-but-OutOfSync artifact.
            # Ignore the fields those trusted managers own so sync status reflects real drift only.
            { group = "argoproj.io", kind = "Rollout", managedFieldsManagers = ["rollouts-controller"] },
            { group = "gateway.networking.k8s.io", kind = "HTTPRoute", managedFieldsManagers = ["cilium-operator-generic"] },
          ]
        }
      }
      # ADR-071: inject the Release digest as a kustomize image override for every Service that has one — the
      # image name MUST match the app overlay's image (<ecr_registry>/team-<team>/<product>-<svc>). Rendered
      # per generated Application (YAML, merged onto it). A Service declared without a digest injects nothing →
      # the overlay's own image governs. The `{{- }}` trims keep the rendered YAML well-indented; `${...}` is
      # Terraform, `{{...}}` is ArgoCD goTemplate.
      templatePatch = <<-EOT
        {{- if hasKey .spec "services" }}
        {{- $any := false }}
        {{- range $svc, $cfg := .spec.services }}{{- if hasKey $cfg "digest" }}{{- $any = true }}{{- end }}{{- end }}
        {{- if $any }}
        spec:
          source:
            kustomize:
              images:
              {{- range $svc, $cfg := .spec.services }}
              {{- if hasKey $cfg "digest" }}
                - "${var.ecr_registry}/team-${each.value.team}/${each.value.product}-{{ $svc }}@{{ $cfg.digest }}"
              {{- end }}
              {{- end }}
        {{- end }}
        {{- end }}
      EOT
    }
  }) })]

  depends_on = [kubernetes_manifest.product_appproject]
}

# ===========================================================================================================
# registry-sync (ADR-069 §1 / #389) — project the git-native Product registry + Environment claims onto the
# cluster as CRs, so Kyverno admission (restrict-environment-envelope) and the Composition can read them. The
# dual-representation contract: delivery derives from the git registry; the cluster reads the projected CRs.
# Mirrors the v2 teams/tenant-claims sync apps. ADDITIVE + GATED on var.platform_repo_url (the gate).
# ===========================================================================================================
locals {
  gitops_registry = var.create && var.platform_repo_url != "" ? { enabled = true } : {}
  # group/kind whitelists for each registry-sync project
  registry_sync = {
    products = { wave = "-2", kinds = [{ group = "platform.refplat.org", kind = "Product" }], path = "gitops/products" }
    # XEnvironment claims (cluster-scoped Crossplane XR) — synced after Teams (-1) and Products (-2) so the
    # envelope/team-matches-product admission inputs land first.
    environments = { wave = "0", kinds = [{ group = "platform.refplat.org", kind = "XEnvironment" }], path = "gitops/environments" }
    # AccessGrant records (cross-team access, ADR-068) — projected for admission + Backstage soft-scoping. Synced
    # after Products so the target Product/Environment exist.
    grants = { wave = "0", kinds = [{ group = "platform.refplat.org", kind = "AccessGrant" }], path = "gitops/grants" }
  }
}

resource "kubernetes_manifest" "registry_project" {
  for_each = length(local.gitops_registry) > 0 ? local.registry_sync : {}

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "AppProject"
    metadata = {
      name      = "platform-${each.key}"
      namespace = var.argocd_namespace
    }
    spec = {
      description = "v3 ${each.key} registry projection (ADR-069 §1)"
      sourceRepos = [var.platform_repo_url]
      destinations = [{
        server    = var.cluster_server
        namespace = "crossplane-system"
      }]
      clusterResourceWhitelist   = each.value.kinds
      namespaceResourceWhitelist = []
    }
  }
}

resource "kubernetes_manifest" "registry_app" {
  for_each = length(local.gitops_registry) > 0 ? local.registry_sync : {}

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = each.key
      namespace = var.argocd_namespace
      labels    = { "platform.refplat.org/component" = each.key }
      annotations = {
        "argocd.argoproj.io/sync-wave" = each.value.wave
      }
    }
    spec = {
      project = "platform-${each.key}"
      source = {
        repoURL        = var.platform_repo_url
        targetRevision = var.platform_repo_branch
        path           = each.value.path
        directory = {
          # the registry is nested per-team/per-product (gitops/<kind>/<team>/<product>.yaml)
          recurse = true
        }
      }
      destination = {
        server    = var.cluster_server
        namespace = "crossplane-system"
      }
      syncPolicy = {
        automated   = { selfHeal = true, prune = true }
        syncOptions = ["CreateNamespace=false", "ServerSideApply=true"]
        retry       = local.sync_retry
      }
    }
  }

  depends_on = [kubernetes_manifest.registry_project]
}
