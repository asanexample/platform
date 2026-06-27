# ===========================================================================================================
# Platform-agent delivery (ADR-082) — the runtime side of ADR-074, on the HUB.
#
# Two pieces, both targeting the HUB (var.hub_cluster_server = ArgoCD's in-cluster), unlike tenant delivery
# which targets the preprod workload cluster (var.cluster_server):
#   1. the `agents` registry-sync — projects gitops/agents/*.yaml (XAgent claims) onto the hub's Crossplane so
#      admission (restrict-agent-envelope) + the Agent Composition reconcile them. Mirrors the environments sync.
#   2. a per-agent workload ApplicationSet — delivers the agent's signed image (the promoted Release digest)
#      into the Composition-made namespace platform-agent-<name>. The Composition owns the agent's
#      ns/SA/identity/RBAC; ArgoCD delivers ONLY the workload (Deployment/Service) — a tight AppProject enforces
#      that split (clusterResourceWhitelist [] — the hub-write blast radius is bounded to namespaced kinds).
#
# NOTE: ApplicationSet generators have NO offline test (like the per-Product appset) — cluster-verification-bound.
# ===========================================================================================================
locals {
  agents = var.create && var.platform_repo_url != "" ? var.agents : {}

  # The Composition-made namespace per agent — platform-agent-<name>, truncate-and-hashed on the 63-char limit
  # identically to the Agent Composition (sha256 6-hex suffix), so the ApplicationSet targets the right ns.
  agent_ns = { for k, v in local.agents : k => (
    length("platform-agent-${k}") > 63
    ? "${substr("platform-agent-${k}", 0, 56)}-${substr(sha256("platform-agent-${k}"), 0, 6)}"
    : "platform-agent-${k}"
  ) }
}

# --- 1. the agents registry-sync (XAgent claims → hub Crossplane) -------------------------------------------
resource "kubernetes_manifest" "agent_registry_project" {
  count = length(local.agents) > 0 ? 1 : 0

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "AppProject"
    metadata = {
      name      = "platform-agents"
      namespace = var.argocd_namespace
    }
    spec = {
      description = "XAgent claim projection onto the hub Crossplane (ADR-082)"
      sourceRepos = [var.platform_repo_url]
      destinations = [{
        server    = var.hub_cluster_server
        namespace = "crossplane-system"
      }]
      clusterResourceWhitelist   = [{ group = "platform.refplat.org", kind = "XAgent" }]
      namespaceResourceWhitelist = []
    }
  }
}

resource "kubernetes_manifest" "agent_registry_app" {
  count = length(local.agents) > 0 ? 1 : 0

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name        = "agents"
      namespace   = var.argocd_namespace
      labels      = { "platform.refplat.org/component" = "agents" }
      annotations = { "argocd.argoproj.io/sync-wave" = "0" }
    }
    spec = {
      project = "platform-agents"
      source = {
        repoURL        = var.platform_repo_url
        targetRevision = var.platform_repo_branch
        path           = "gitops/agents"
        directory      = { recurse = true }
      }
      destination = {
        server    = var.hub_cluster_server
        namespace = "crossplane-system"
      }
      syncPolicy = {
        automated   = { selfHeal = true, prune = true }
        syncOptions = ["CreateNamespace=false", "ServerSideApply=true"]
        retry       = local.sync_retry
      }
    }
  }

  depends_on = [kubernetes_manifest.agent_registry_project]
}

# --- 2. per-agent workload delivery (the signed image → the hub agent namespace) ----------------------------
resource "kubernetes_manifest" "agent_appproject" {
  for_each = local.agents

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "AppProject"
    metadata = {
      name      = "agent-${each.key}"
      namespace = var.argocd_namespace
    }
    spec = {
      description = "workload delivery for platform agent ${each.key}"
      sourceRepos = [each.value.repo_url]
      destinations = [{
        server    = var.hub_cluster_server
        namespace = local.agent_ns[each.key]
      }]
      # ArgoCD delivers ONLY the workload — the agent's ns/SA/identity/RBAC come from the Composition (gated IaC),
      # NEVER from ArgoCD (the hub-write blast radius, ADR-082 D8). clusterResourceWhitelist [] = no cluster-scoped
      # writes; ServiceAccount is NOT whitelisted (the Composition owns it — the app must drop its SA manifest).
      clusterResourceWhitelist = []
      namespaceResourceWhitelist = [
        { group = "", kind = "ConfigMap" },
        { group = "", kind = "Service" },
        { group = "apps", kind = "Deployment" },
        { group = "external-secrets.io", kind = "ExternalSecret" },
        # The agent's in-process directory Postgres (ADR-084 Phase 1) — a CNPG Cluster the operator reconciles.
        { group = "postgresql.cnpg.io", kind = "Cluster" },
      ]
    }
  }
}

resource "helm_release" "agent_appset" {
  for_each = local.agents

  name             = "agent-${each.key}"
  namespace        = var.argocd_namespace
  chart            = "${path.module}/charts/applicationset-raw"
  create_namespace = false

  # Same B-via-Helm passthrough as the per-Product appset: kubernetes_manifest can't represent the generator
  # schema, so build the manifest as data and let Helm emit it verbatim (ArgoCD's {{ }} survive).
  values = [yamlencode({ manifest = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "ApplicationSet"
    metadata = {
      name      = "agent-${each.key}"
      namespace = var.argocd_namespace
      labels    = { "platform.refplat.org/agent" = each.key }
    }
    spec = {
      goTemplate        = true
      goTemplateOptions = ["missingkey=error"]
      # Fan out over the agent's product Release records for the signed digest (ADR-071). A hub agent is a SINGLE
      # instance, so it expects exactly ONE active Release (v1): a second would generate a duplicate-named
      # Application (ArgoCD rejects it — fail-loud). Decoupling the agent digest from the tenant stage-Release
      # (e.g. promoting into the XAgent claim) is a documented follow-up.
      generators = [{
        git = {
          repoURL  = var.platform_repo_url
          revision = "HEAD"
          files    = [{ path = "gitops/releases/${each.value.team}/${each.value.product}/*.yaml" }]
        }
      }]
      template = {
        metadata = {
          name   = "agent-${each.key}"
          labels = { "platform.refplat.org/agent" = each.key }
        }
        spec = {
          project = "agent-${each.key}"
          source = {
            repoURL        = each.value.repo_url
            targetRevision = "HEAD"
            # The per-stage overlay (carries non-digest config); the digest is injected by templatePatch below.
            path = "k8s/overlays/{{ splitList \"-\" .spec.environmentRef | last }}"
          }
          destination = {
            server    = var.hub_cluster_server
            namespace = local.agent_ns[each.key] # the Composition-made platform-agent-<name>
          }
          syncPolicy = {
            automated   = { selfHeal = true, prune = true }
            syncOptions = ["CreateNamespace=false"]
            retry       = local.first_deploy_retry
          }
        }
      }
      # Inject the Release digest as a kustomize image override (image name = the app overlay's image,
      # <ecr_registry>/team-<team>/<product>-<svc>). HEREDOC (not yamlencode) so the goTemplate quotes survive.
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

  depends_on = [kubernetes_manifest.agent_appproject]
}
