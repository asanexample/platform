/**
 * # Cilium CNI Installation Module
 *
 * This module installs Cilium CNI using the Helm provider on an AKS cluster.
 * It's designed to work with clusters that have network_plugin set to "none" to allow Cilium
 * to take over the networking responsibilities.
 */

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11.0"
    }
  }
}

# Cilium namespace
resource "kubernetes_namespace" "cilium" {
  metadata {
    name = var.namespace
    labels = merge(var.namespace_labels, {
      name = var.namespace
    })
  }
}

# Install Cilium using Helm
resource "helm_release" "cilium" {
  name       = "cilium"
  namespace  = kubernetes_namespace.cilium.metadata[0].name
  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  version    = var.chart_version
  timeout    = var.helm_timeout
  wait       = var.wait

  values = [
    var.values_file != "" ? file(var.values_file) : "",
    var.values_content
  ]

  # Construct dynamic set values from the inputs
  dynamic "set" {
    for_each = var.set_values
    content {
      name  = set.key
      value = set.value
    }
  }

  # Default Cilium configuration values if none are provided
  dynamic "set" {
    for_each = var.set_values == {} ? {
      "aks.enabled"                 = "true"
      "tunnel"                      = "vxlan"
      "ipam.mode"                   = "kubernetes"
      "kubeProxyReplacement"        = "strict"
      "k8sServiceHost"              = var.kubernetes_host
      "k8sServicePort"              = var.kubernetes_port
      "hubble.enabled"              = "true"
      "hubble.relay.enabled"        = "true"
      "hubble.ui.enabled"           = "true"
      "operator.replicas"           = var.operator_replicas
      "nodeinit.enabled"            = "true"
      "prometheus.enabled"          = var.prometheus_enabled
      "prometheus.serviceMonitor.enabled" = var.prometheus_service_monitor_enabled
    } : {}
    content {
      name  = set.key
      value = set.value
    }
  }

  depends_on = [
    kubernetes_namespace.cilium
  ]
} 