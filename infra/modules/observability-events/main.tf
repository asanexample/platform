locals {
  create = var.create

  # ---- Alloy River config: watch K8s Events cluster-wide -> Loki (tenant _platform) ----
  # loki.source.kubernetes_events watches the Events API and emits each event as a log line. Deployed as
  # a SINGLETON Deployment — multiple replicas would each watch the API and duplicate every event.
  events_config = <<-RIVER
    // All namespaces' events.
    loki.source.kubernetes_events "events" {
      forward_to = [loki.write.platform.receiver]
    }

    loki.write "platform" {
      endpoint {
        url       = "${var.loki_push_url}"
        tenant_id = "${var.tenant_id}"
      }
    }
  RIVER

  helm_values = {
    fullnameOverride = var.helm_release_name

    crds           = { create = false }
    configReloader = { enabled = false } # static River config (managed via Terragrunt/helm)

    serviceAccount = { create = true, name = var.helm_release_name }
    rbac           = { create = true } # ClusterRole includes events get/list/watch

    controller = {
      type     = "deployment"
      replicas = 1 # singleton: >1 would duplicate every event into Loki
    }

    alloy = {
      configMap       = { create = true, content = local.events_config }
      clustering      = { enabled = false }
      stabilityLevel  = "generally-available"
      enableReporting = false

      resources = {
        requests = { cpu = "20m", memory = "128Mi" }
        limits   = { memory = "256Mi" }
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Helm release — grafana/alloy (K8s events -> Loki, singleton Deployment)
# ---------------------------------------------------------------------------

resource "helm_release" "events" {
  count = local.create ? 1 : 0

  name             = var.helm_release_name
  repository       = var.helm_repository
  chart            = var.helm_chart
  version          = var.helm_chart_version
  namespace        = var.namespace
  create_namespace = false # the observability module owns the namespace (PSA label)
  timeout          = var.helm_timeout
  wait             = var.helm_wait
  atomic           = var.helm_wait
  cleanup_on_fail  = true

  values = [yamlencode(local.helm_values)]
}
