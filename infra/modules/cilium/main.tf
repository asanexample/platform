/**
 * ## Cilium Helm Module
 *
 * Deploys Cilium CNI via Helm. Supports Azure (AKS), AWS (EKS), and GCP (GKE).
 */

locals {
  # Prepare Kubernetes labels from tags, replacing any characters not allowed in labels
  k8s_labels = {
    for k, v in var.tags :
    replace(lower(k), "/[^a-z0-9_.-]/", "_") => replace(lower(v), "/[^a-z0-9_.-]/", "_")
    if length(replace(lower(k), "/[^a-z0-9_.-]/", "_")) <= 63 && length(replace(lower(v), "/[^a-z0-9_.-]/", "_")) <= 63
  }

  cloud_values_yaml = {
    aws = yamlencode({
      eni                        = { enabled = true }
      ipam                       = { mode = "eni" }
      egressMasqueradeInterfaces = "ens+"
      routingMode                = "native"
      hubble = {
        tls = {
          auto = {
            method = "helm"
          }
        }
      }
    })
    azure = yamlencode({
      aksbyocni = { enabled = true }
      nodeinit  = { enabled = true }
    })
    gcp = yamlencode({
      gke         = { enabled = true }
      ipam        = { mode = "kubernetes" }
      routingMode = "native"
    })
  }

  k8s_api_values_yaml = var.k8s_service_host != "" ? yamlencode({
    k8sServiceHost = var.k8s_service_host
    k8sServicePort = var.k8s_service_port
  }) : yamlencode({})

  cilium_values = {
    # Gateway API support
    gatewayAPI = {
      enabled = var.gateway_api_enabled
    }
    gatewayClass = {
      create = var.gateway_api_enabled
    }

    # Kube-proxy replacement
    kubeProxyReplacement = var.kube_proxy_replacement

    # TLS configuration
    tls = var.tls

    # Debug mode
    debug = var.debug

    # Identity allocation mode
    identityAllocationMode = var.identityAllocationMode

    # CNI configuration
    cni = var.cni

    # Enable NodePort
    nodePort = {
      enabled = var.node_port_enabled
    }

    # Enable ExternalIPs
    externalIPs = {
      enabled = var.external_ips_enabled
    }

    # Socket LB configuration
    socketLB = {
      hostNamespaceOnly = var.socket_lb_host_namespace_only
    }

    # Prometheus configuration
    prometheus = {
      enabled = var.prometheus_enabled
      serviceMonitor = {
        enabled = false # Disable ServiceMonitor
      }
    }

    operator = {
      prometheus = {
        enabled = var.operator_prometheus_enabled
        serviceMonitor = {
          enabled = false # Disable ServiceMonitor
        }
      }
      resources = {
        limits = {
          cpu    = var.operator_resources_limits_cpu
          memory = var.operator_resources_limits_memory
        }
        requests = {
          cpu    = var.operator_resources_requests_cpu
          memory = var.operator_resources_requests_memory
        }
      }
    }

    # Hubble configuration
    hubble = {
      enabled       = var.hubble_enabled
      listenAddress = var.hubble_listen_address
      metrics = {
        enabled           = var.hubble_metrics_enabled
        enableOpenMetrics = var.hubble_metrics_enable_open_metrics
        serviceMonitor = {
          enabled = false # Disable ServiceMonitor
        }
      }
      relay = {
        enabled = var.hubble_relay_enabled
        serviceMonitor = {
          enabled = false # Disable ServiceMonitor
        }
      }
      ui = {
        enabled = var.hubble_ui_enabled
        serviceMonitor = {
          enabled = false # Disable ServiceMonitor
        }
      }
      tls = {
        auto = {
          enabled              = var.hubble_tls_auto_enabled
          method               = var.hubble_tls_auto_method
          certValidityDuration = var.hubble_tls_cert_validity_duration
          schedule             = var.hubble_tls_schedule
        }
      }
    }

    # Resource limits
    resources = {
      limits = {
        cpu    = var.resources_limits_cpu
        memory = var.resources_limits_memory
      }
      requests = {
        cpu    = var.resources_requests_cpu
        memory = var.resources_requests_memory
      }
    }

    # Labels from tags
    podLabels = local.k8s_labels
  }
}

# ---------------------------------------------------------------------------
# Gateway API CRDs — required before Cilium can reconcile Gateway resources
# ---------------------------------------------------------------------------

resource "null_resource" "gateway_api_crds" {
  count = var.create && var.gateway_api_enabled && var.gateway_api_crd_version != "" ? 1 : 0

  triggers = {
    version = var.gateway_api_crd_version
  }

  provisioner "local-exec" {
    command = "${var.kubeconfig_path != "" ? "kubectl --kubeconfig=${var.kubeconfig_path}" : "kubectl"} apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/${var.gateway_api_crd_version}/experimental-install.yaml"
  }
}

# Install Cilium using Helm
resource "helm_release" "cilium" {
  count            = var.create ? 1 : 0
  name             = var.helm_release_name
  repository       = var.helm_repository
  chart            = var.helm_chart
  version          = var.helm_chart_version
  namespace        = var.namespace
  create_namespace = false
  timeout          = var.helm_timeout
  wait             = var.helm_wait
  atomic           = var.helm_wait
  cleanup_on_fail  = true
  replace          = true

  depends_on = [null_resource.gateway_api_crds]

  values = [
    yamlencode(local.cilium_values),
    local.cloud_values_yaml[var.cloud_provider],
    local.k8s_api_values_yaml,
  ]

  set = [
    {
      name = "configHash"
      value = sha256(join("", [
        yamlencode(local.cilium_values),
        local.cloud_values_yaml[var.cloud_provider],
        local.k8s_api_values_yaml,
      ]))
    },
  ]
}
