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

  # Datapath config, driven entirely by variables (cloud-agnostic). Each merge
  # fragment contributes distinct top-level keys, so the shallow merge is safe.
  datapath_values = merge(
    {
      routingMode          = var.routing_mode
      enableIPv4Masquerade = var.enable_ipv4_masquerade
      ipam = merge(
        { mode = var.ipam_mode },
        var.ipam_mode == "cluster-pool" ? {
          operator = {
            clusterPoolIPv4PodCIDRList = [var.pod_cidr]
            clusterPoolIPv4MaskSize    = var.pod_cidr_mask_size
          }
        } : {}
      )
    },
    # Encapsulation only applies in tunnel mode; clear it in native mode.
    { tunnelProtocol = var.routing_mode == "tunnel" ? var.tunnel_protocol : "" },
    var.bpf_masquerade ? { bpf = { masquerade = true } } : {},
    var.egress_masquerade_interfaces != "" ? { egressMasqueradeInterfaces = var.egress_masquerade_interfaces } : {},
    var.routing_mode == "native" && var.native_routing_cidr != "" ? { ipv4NativeRoutingCIDR = var.native_routing_cidr } : {},
    var.mtu > 0 ? { MTU = var.mtu } : {},
    # Transparent encryption (ADR-057 Phase 1) — WireGuard/IPsec on the wire between nodes.
    var.encryption_enabled ? { encryption = { enabled = true, type = var.encryption_type, nodeEncryption = var.node_encryption } } : {},
  )

  # Irreducible per-cloud plumbing — NOT the datapath (that's variable-driven above).
  cloud_plumbing = {
    aws = merge(
      {
        kubeProxyReplacement = true                                     # Required: EKS BYOCNI deploys no kube-proxy DaemonSet
        hubble               = { tls = { auto = { method = "helm" } } } # Avoids BYOCNI post-install hook chicken-and-egg
      },
      # ENI native routing needs the ENI datapath + ARP resolution; omit in overlay.
      var.ipam_mode == "eni" ? {
        eni              = { enabled = true }
        l2NeighDiscovery = { enabled = true }
      } : {}
    )
    azure = {
      aksbyocni = { enabled = true }
      nodeinit  = { enabled = true }
    }
    gcp = {
      gke = { enabled = true }
    }
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

    # Service-to-service mutual authentication (ADR-057 Phase 2) — SPIFFE identity via the embedded SPIRE.
    # `enabled` MUST be true for auth requests to be processed (else auth-required policies deny). SPIRE is
    # only installed when spire.enabled is true, so this block is inert when mutual_auth_enabled = false
    # (matches chart defaults). Enforcement applies only to CNPs that opt in with authentication.mode: required.
    authentication = {
      enabled = var.mutual_auth_enabled
      mutual = {
        spire = {
          enabled = var.mutual_auth_enabled
          install = {
            enabled = var.spire_install
            # SPIRE server datastore. Persistent needs a PVC + (where an SCP enforces EBS encryption) an
            # encrypted StorageClass; null = the cluster default (encrypted gp3). enabled=false = in-memory.
            server = {
              # The SPIRE server mints its CA with rsa-4096 keys — CPU-heavy. With no request it runs
              # BestEffort, and when scheduled onto a small/contended node the keygen starves past the
              # KeyManager deadline ("Unable to rotate X509 CA: keymanager(disk): context deadline
              # exceeded"), crash-looping the server and wedging fleet-wide mutual auth. Guarantee CPU and
              # allow a burst to a full core for keygen so it schedules with headroom and rotates the CA
              # reliably (esp. post-unpark, when it may land on a saturated 1-vCPU node). Postmortem 2026-07-10.
              resources = {
                requests = { cpu = "250m", memory = "128Mi" }
                limits   = { cpu = "1", memory = "512Mi" }
              }
              dataStorage = {
                enabled      = var.spire_persistence
                storageClass = var.spire_storage_class
              }
            }
          }
        }
      }
    }
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
    # Experimental channel includes GRPCRoute, TCPRoute, and TLSRoute CRDs
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
  create_namespace = false # kube-system always exists
  timeout          = var.helm_timeout
  wait             = var.helm_wait
  atomic           = var.helm_wait
  cleanup_on_fail  = true
  replace          = true

  depends_on = [null_resource.gateway_api_crds]

  # Helm deep-merges these in order: generic <- datapath (variable-driven) <-
  # per-cloud plumbing <- k8s API. Later docs win on shared leaf keys
  # (e.g. cloud plumbing's hubble.tls.auto.method=helm overrides the generic default).
  values = [
    yamlencode(local.cilium_values),
    yamlencode(local.datapath_values),
    yamlencode(local.cloud_plumbing[var.cloud_provider]),
    local.k8s_api_values_yaml,
  ]

  set = [
    {
      name = "configHash"
      value = sha256(join("", [
        yamlencode(local.cilium_values),
        yamlencode(local.datapath_values),
        yamlencode(local.cloud_plumbing[var.cloud_provider]),
        local.k8s_api_values_yaml,
      ]))
    },
  ]

  lifecycle {
    precondition {
      condition     = !(var.ipam_mode == "cluster-pool" && var.pod_cidr == "")
      error_message = "pod_cidr must be set when ipam_mode = \"cluster-pool\"."
    }
    precondition {
      condition     = !(var.routing_mode == "native" && var.ipam_mode != "eni" && var.native_routing_cidr == "")
      error_message = "native_routing_cidr must be set when routing_mode = \"native\" and ipam_mode is not \"eni\"."
    }
    precondition {
      condition     = !(var.bpf_masquerade && var.egress_masquerade_interfaces != "")
      error_message = "egress_masquerade_interfaces must be empty when bpf_masquerade = true (eBPF masquerade ignores the interface glob and would silently fall back to iptables)."
    }
    precondition {
      condition     = var.ipam_mode != "cluster-pool" || var.pod_cidr == "" || var.pod_cidr_mask_size > tonumber(split("/", var.pod_cidr)[1])
      error_message = "pod_cidr_mask_size must be more specific (numerically greater) than the pod_cidr prefix length."
    }
  }
}
