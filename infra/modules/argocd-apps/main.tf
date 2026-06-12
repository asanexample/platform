locals {
  create = var.create

  # Sync retry for every Application targeting the remote (preprod) cluster. Without it, ArgoCD abandons a
  # failed sync after 5 attempts on a revision and won't auto-retry until the revision changes — so a transient
  # bootstrap window (the lockdown's EKS endpoint toggle churns the API ENIs and the cross-vpc-dns PHZ record
  # lags; CRDs registering; cluster cache warming) leaves apps stuck SyncFailed/Unknown until a human syncs.
  # ~12 attempts over ~45 min rides out any such window; steady-state syncs are unaffected (retry only fires
  # on failure).
  sync_retry = {
    limit = 12
    backoff = {
      duration    = "30s"
      factor      = 2
      maxDuration = "5m"
    }
  }

  # Fail-FAST retry for the per-Product ApplicationSet's generated Applications (v3-delivery). Their first
  # deploy is special: a brand-new Environment's app overlay carries `:placeholder` (no digest yet) until the
  # app's first CI build commits the signed-digest pin — a SEPARATE commit after the build-trigger push. ArgoCD
  # auto-syncs the pre-pin revision, Kyverno verify-images-product rejects the unpinned image, and the long
  # sync_retry above then keeps the operation hammering that stale revision for ~45 min, holding the lock so
  # selfHeal can't pick up the pin commit until a human `argocd app terminate-op`s it. A short, low-limit retry
  # makes the doomed pre-pin sync give up in ~minutes; the pin commit is a revision change, so selfHeal then
  # auto-syncs HEAD and converges with no manual step. Steady-state deploys are unaffected (the overlay already
  # carries a valid digest, so the sync succeeds and retry never fires). See docs/runbooks/v3-cutover.md.
  first_deploy_retry = {
    limit = 4
    backoff = {
      duration    = "15s"
      factor      = 2
      maxDuration = "2m"
    }
  }
}

# ---------------------------------------------------------------------------
# Git-native Team objects (ADR-063): a dedicated AppProject + Application that
# syncs the cluster-scoped Team CRs from git. Replaces the crossplane-teams Helm
# projection (the crossplane unit now passes var.teams = {}); the Team CRD itself
# still ships with the crossplane chart. The Team CR is what Kyverno reads during
# XEnvironment admission (restrict-environment-envelope + team-matches-product), so
# this app must reconcile BEFORE the environments registry-sync app: the sync-wave
# annotation declares that priority, and ArgoCD's selfHeal converges the case where
# an Environment is transiently rejected because its Team is not yet applied
# (eventual GitOps consistency — the next reconcile admits it once the Team CR exists).
# ---------------------------------------------------------------------------

resource "kubernetes_manifest" "teams_project" {
  for_each = var.enable_teams ? { enabled = true } : {}

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "AppProject"
    metadata = {
      name      = "platform-teams"
      namespace = var.argocd_namespace
    }
    spec = {
      description = "Git-native Team governance objects (platform-managed, ADR-063)"
      sourceRepos = [var.teams_repo_url]
      destinations = [{
        server    = var.cluster_server
        namespace = "crossplane-system"
      }]
      # Only the cluster-scoped Team — nothing else.
      clusterResourceWhitelist = [
        { group = "platform.refplat.org", kind = "Team" },
      ]
      namespaceResourceWhitelist = []
    }
  }
}

resource "kubernetes_manifest" "teams_app" {
  for_each = var.enable_teams ? { enabled = true } : {}

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "teams"
      namespace = var.argocd_namespace
      labels = {
        "platform.refplat.org/component" = "teams"
      }
      # Sync-wave priority: Teams ahead of the environments registry-sync app (default wave 0),
      # so the envelope/team-matches-product admission inputs land first.
      annotations = {
        "argocd.argoproj.io/sync-wave" = "-1"
      }
    }
    spec = {
      project = "platform-teams"
      source = {
        repoURL        = var.teams_repo_url
        targetRevision = var.teams_repo_branch
        path           = var.teams_repo_path
      }
      destination = {
        server    = var.cluster_server
        namespace = "crossplane-system"
      }
      # Git is the source of truth: prune offboards a Team when its YAML is removed
      # (gated by CODEOWNERS on the teams path). ServerSideApply so the status
      # subresource (rollup controller) is not stripped by selfHeal.
      syncPolicy = {
        automated = {
          selfHeal = true
          prune    = true
        }
        syncOptions = ["CreateNamespace=false", "ServerSideApply=true"]
        retry       = local.sync_retry
      }
    }
  }

  depends_on = [kubernetes_manifest.teams_project]
}

