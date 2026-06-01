/**
 * # Cilium Module Variables
 */

# Installation control
variable "create" {
  description = "Controls whether Cilium resources should be created"
  type        = bool
  default     = true
}

variable "cloud_provider" {
  description = "Cloud provider for platform-specific CNI config"
  type        = string
  default     = "aws"
  validation {
    condition     = contains(["azure", "aws", "gcp"], var.cloud_provider)
    error_message = "cloud_provider must be 'azure', 'aws', or 'gcp'"
  }
}

# ---------------------------------------------------------------------------
# Datapath / pod networking
#
# These control how pods get IPs and how pod traffic is carried. Defaults
# select an OVERLAY datapath (cluster-pool IPAM + VXLAN tunnel): pod IPs come
# from `pod_cidr` and are decoupled from the VPC, so a cluster can run many
# more pods than the node subnets could hold. Set ipam_mode="eni" +
# routing_mode="native" (+ egress_masquerade_interfaces="ens+") to use AWS
# VPC-native routing instead (pods get routable VPC IPs).
# ---------------------------------------------------------------------------

variable "ipam_mode" {
  description = "Cilium IPAM mode: cluster-pool (overlay), eni (AWS VPC-native), or kubernetes (host-scope)."
  type        = string
  default     = "cluster-pool"
  validation {
    condition     = contains(["cluster-pool", "eni", "kubernetes"], var.ipam_mode)
    error_message = "ipam_mode must be 'cluster-pool', 'eni', or 'kubernetes'."
  }
}

variable "routing_mode" {
  description = "Cilium routing mode: tunnel (encapsulated overlay) or native (no encapsulation)."
  type        = string
  default     = "tunnel"
  validation {
    condition     = contains(["tunnel", "native"], var.routing_mode)
    error_message = "routing_mode must be 'tunnel' or 'native'."
  }
}

variable "tunnel_protocol" {
  description = "Encapsulation protocol when routing_mode = tunnel. Ignored otherwise."
  type        = string
  default     = "vxlan"
  validation {
    condition     = contains(["vxlan", "geneve"], var.tunnel_protocol)
    error_message = "tunnel_protocol must be 'vxlan' or 'geneve'."
  }
}

variable "pod_cidr" {
  description = "IPv4 pool for cluster-pool IPAM (required when ipam_mode = cluster-pool). Must be non-routable on the VPC and distinct from the VPC and service CIDRs. Empty for eni/kubernetes IPAM."
  type        = string
  default     = ""
  validation {
    condition     = var.pod_cidr == "" || can(cidrnetmask(var.pod_cidr))
    error_message = "pod_cidr must be empty or a valid IPv4 CIDR (e.g. 10.240.0.0/16)."
  }
}

variable "pod_cidr_mask_size" {
  description = "Per-node block size carved from pod_cidr for cluster-pool IPAM (e.g. 24 = 256 IPs/node)."
  type        = number
  default     = 24
  validation {
    condition     = var.pod_cidr_mask_size > 0 && var.pod_cidr_mask_size <= 32
    error_message = "pod_cidr_mask_size must be between 1 and 32."
  }
}

variable "enable_ipv4_masquerade" {
  description = "Masquerade pod egress to the node IP for traffic leaving the cluster."
  type        = bool
  default     = true
}

variable "egress_masquerade_interfaces" {
  description = "Interface glob to masquerade on (e.g. 'ens+' for ENI native). Empty = all interfaces (overlay default). Must be empty when bpf_masquerade = true."
  type        = string
  default     = ""
}

variable "bpf_masquerade" {
  description = "Use eBPF masquerade instead of iptables. Requires kubeProxyReplacement and an empty egress_masquerade_interfaces (BPF masquerade ignores the interface glob)."
  type        = bool
  default     = false
}

variable "native_routing_cidr" {
  description = "CIDR that Cilium treats as natively routable (no masquerade within it). Required when routing_mode = native AND ipam_mode != eni; ENI mode auto-derives it."
  type        = string
  default     = ""
  validation {
    condition     = var.native_routing_cidr == "" || can(cidrnetmask(var.native_routing_cidr))
    error_message = "native_routing_cidr must be empty or a valid IPv4 CIDR."
  }
}

variable "mtu" {
  description = "Override the device MTU. 0 = auto-detect (Cilium subtracts tunnel overhead). Pin to 1500 if jumbo frames cause PMTU black-holing on egress."
  type        = number
  default     = 0
  validation {
    condition     = var.mtu >= 0
    error_message = "mtu must be >= 0 (0 = auto)."
  }
}

variable "k8s_service_host" {
  description = "Kubernetes API server hostname (required for BYOCNI — in-cluster service IP unreachable before CNI exists)"
  type        = string
  default     = ""
}

variable "k8s_service_port" {
  description = "Kubernetes API server port"
  type        = string
  default     = "443"
}

# Environment variables
variable "environment" {
  description = "Environment name (e.g., dev, test, prod)"
  type        = string
  default     = "dev"
}

variable "workload" {
  description = "Workload identifier for resource naming"
  type        = string
  default     = "platform"
}

variable "region_abbv" {
  description = "Abbreviated name of the region (e.g., eus for eastus)"
  type        = string
  default     = ""
}

variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
}

variable "kubeconfig_path" {
  description = "Path to a kubeconfig file for kubectl operations. If empty, uses the default kubeconfig."
  type        = string
  default     = ""
}

variable "resource_group_name" {
  description = "Name of the Azure resource group (only required for Azure)"
  type        = string
  default     = ""
}

# Tags
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Helm release details
variable "helm_release_name" {
  description = "Name of the Helm release for Cilium"
  type        = string
  default     = "cilium"
}

variable "helm_repository" {
  description = "Repository URL for the Cilium Helm chart"
  type        = string
  default     = "https://helm.cilium.io/"
}

variable "helm_chart" {
  description = "Name of the Cilium Helm chart"
  type        = string
  default     = "cilium"
}

variable "helm_chart_version" {
  description = "Version of the Cilium Helm chart"
  type        = string
  default     = "1.19.4"
}

variable "namespace" {
  description = "Kubernetes namespace to install Cilium into"
  type        = string
  default     = "kube-system"
}

variable "helm_timeout" {
  description = "Timeout for Helm operations in seconds"
  type        = number
  default     = 1200
}

variable "helm_wait" {
  description = "Whether to wait for Helm release to complete"
  type        = bool
  default     = true
}

# Cilium configuration values

variable "gateway_api_enabled" {
  description = "Enable Gateway API support"
  type        = bool
  default     = true
}

variable "gateway_api_crd_version" {
  description = "Gateway API CRD version to install (experimental channel). Set to empty string to skip CRD installation."
  type        = string
  default     = "v1.3.0"
}

variable "kube_proxy_replacement" {
  description = "KubeProxy replacement mode (false, 'strict', 'partial', 'probe')"
  type        = string
  # On AWS, this is overridden to true by cloud_values_yaml (required for BYOCNI).
  # This default only applies to Azure/GCP.
  default = "false"
}

variable "node_port_enabled" {
  description = "Enable NodePort service support"
  type        = bool
  default     = true
}

variable "external_ips_enabled" {
  description = "Enable ExternalIPs service support"
  type        = bool
  default     = true
}

variable "cni_exclusive" {
  description = "Make Cilium take ownership over the container runtime CNI configuration"
  type        = bool
  default     = false
}

variable "socket_lb_host_namespace_only" {
  description = "Force socket LB in host namespace only"
  type        = bool
  default     = true
}

# Prometheus configuration
variable "prometheus_enabled" {
  description = "Enable Prometheus metrics for Cilium agent"
  type        = bool
  default     = true
}

variable "prometheus_service_monitor_enabled" {
  description = "Enable Prometheus ServiceMonitor for Cilium agent"
  type        = bool
  default     = true
}

variable "operator_prometheus_enabled" {
  description = "Enable Prometheus metrics for Cilium operator"
  type        = bool
  default     = true
}

# TLS configuration
variable "tls" {
  description = "TLS configuration for Cilium"
  type        = any
  default = {
    enabled = false
  }
}

# Debug configuration
variable "debug" {
  description = "Debug configuration for Cilium"
  type        = any
  default = {
    enabled = false
  }
}

# Identity allocation mode
variable "identityAllocationMode" {
  description = "The method to use for identity allocation (CRD or kvstore)"
  type        = string
  default     = "crd"
}

# CNI configuration
variable "cni" {
  description = "CNI configuration for Cilium"
  type        = any
  default = {
    exclusive    = false
    chainingMode = null
  }
}

# Hubble configuration
variable "hubble_enabled" {
  description = "Enable Hubble"
  type        = bool
  default     = true
}

variable "hubble_listen_address" {
  description = "Hubble listen address"
  type        = string
  default     = ":4244"
}

variable "hubble_metrics_enabled" {
  description = "List of Hubble metrics to enable"
  type        = list(string)
  default = [
    "dns:labelsContext=source_namespace,destination_namespace",
    "drop:labelsContext=source_namespace,destination_namespace",
    "tcp",
    "flow",
    "port-distribution",
    "icmp",
    "httpV2:sourceContext=workload-name|pod-name|reserved-identity;destinationContext=workload-name|pod-name|reserved-identity;labelsContext=source_namespace,destination_namespace,traffic_direction"
  ]
}

variable "hubble_metrics_enable_open_metrics" {
  description = "Enable OpenMetrics format for Hubble metrics"
  type        = bool
  default     = false
}

variable "hubble_relay_enabled" {
  description = "Enable Hubble Relay"
  type        = bool
  default     = true
}

variable "hubble_ui_enabled" {
  description = "Enable Hubble UI"
  type        = bool
  default     = true
}

variable "hubble_tls_auto_enabled" {
  description = "Enable automatic TLS certificate generation for Hubble"
  type        = bool
  default     = true
}

variable "hubble_tls_auto_method" {
  description = "Method to auto-generate TLS certificates (cronJob or certmanager)"
  type        = string
  default     = "cronJob"
}

variable "hubble_tls_cert_validity_duration" {
  description = "Validity duration of the Hubble TLS certificates in days"
  type        = number
  default     = 1095 # 3 years
}

variable "hubble_tls_schedule" {
  description = "Cron schedule for Hubble TLS certificate generation"
  type        = string
  default     = "0 0 1 */4 *" # Midnight on 1st of every 4th month
}

# Resource limits
variable "resources_limits_cpu" {
  description = "CPU limit for Cilium agent"
  type        = string
  default     = "1000m"
}

variable "resources_limits_memory" {
  description = "Memory limit for Cilium agent"
  type        = string
  default     = "1Gi"
}

variable "resources_requests_cpu" {
  description = "CPU request for Cilium agent"
  type        = string
  default     = "100m"
}

variable "resources_requests_memory" {
  description = "Memory request for Cilium agent"
  type        = string
  default     = "128Mi"
}

variable "operator_resources_limits_cpu" {
  description = "CPU limit for Cilium operator"
  type        = string
  default     = "500m"
}

variable "operator_resources_limits_memory" {
  description = "Memory limit for Cilium operator"
  type        = string
  default     = "512Mi"
}

variable "operator_resources_requests_cpu" {
  description = "CPU request for Cilium operator"
  type        = string
  default     = "50m"
}

variable "operator_resources_requests_memory" {
  description = "Memory request for Cilium operator"
  type        = string
  default     = "64Mi"
} 