locals {
  create = var.create

  helm_values = {
    replicas = var.replicas

    config = {
      listen = "0.0.0.0:8080"
      target = var.mimir_push_url
      # Suppress the noisy per-sample 400/429 logs — Mimir's own distributor already reports these,
      # and out-of-order/limit rejections during rollout would otherwise flood cortex-tenant's logs.
      log_response_errors = false

      tenant = {
        # Route on a normal (non-`__`) label the write-path relabel sets to the team; strip it so it
        # is never stored. Missing label → default_tenant (platform infra), never a 400/drop.
        label        = var.routing_label
        label_remove = true
        header       = "X-Scope-OrgID"
        default      = var.default_tenant
      }
    }

    # It is on the write path — keep it schedulable and give it a PDB-friendly replica count.
    resources = {
      requests = { cpu = "50m", memory = "128Mi" }
      limits   = { memory = "256Mi" }
    }

    serviceMonitor = {
      enabled = var.create_service_monitor
    }
  }
}

resource "helm_release" "cortex_tenant" {
  count = local.create ? 1 : 0

  name       = "cortex-tenant"
  repository = var.helm_repository
  chart      = var.helm_chart
  version    = var.helm_chart_version
  namespace  = var.namespace

  timeout = var.helm_timeout
  wait    = true
  atomic  = true

  values = [yamlencode(local.helm_values)]
}
