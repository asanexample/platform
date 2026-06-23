locals {
  create = var.create

  river_config = templatefile("${path.module}/river-config.alloy", {
    pyroscope_url = var.pyroscope_url
    tenant_id     = var.tenant_id
  })

  # Privileged Alloy DaemonSet — eBPF needs elevated kernel privileges + host PID visibility (same as the
  # Beyla eBPF DaemonSet; the observability namespace is already PSA `privileged`).
  helm_values = {
    controller = {
      type    = "daemonset"
      hostPID = true
    }

    alloy = {
      configMap = { content = local.river_config }

      securityContext = {
        privileged = true
        runAsUser  = 0
      }

      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { memory = "512Mi" }
      }
    }

    # Alloy's own metrics aren't needed here; keep the footprint minimal.
    serviceMonitor = { enabled = false }
  }
}

resource "helm_release" "alloy_profiles" {
  count = local.create ? 1 : 0

  name             = var.helm_release_name
  repository       = var.helm_repository
  chart            = "alloy"
  version          = var.helm_chart_version
  namespace        = var.namespace
  create_namespace = false
  timeout          = var.helm_timeout
  wait             = var.helm_wait
  atomic           = var.helm_wait
  cleanup_on_fail  = true

  values = [yamlencode(local.helm_values)]
}
