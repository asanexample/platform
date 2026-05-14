/**
 * # Policy Helm Module
 *
 * This module deploys Kyverno (a Kubernetes-native policy engine) via Helm
 * and applies baseline ClusterPolicy resources for compliance guardrails.
 */

locals {
  # TODO: Add compliance-tier-specific policies in a future iteration.
  # - standard: baseline best practices (require labels, disallow privileged containers)
  # - hipaa:    audit logging, encryption-at-rest enforcement, access controls
  # - pci:      network isolation, image allowlisting, secret rotation policies
}

# Install Kyverno using Helm
resource "helm_release" "kyverno" {
  count            = var.create ? 1 : 0
  name             = "kyverno"
  repository       = "https://kyverno.github.io/kyverno/"
  chart            = "kyverno"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = true
  timeout          = 600
  wait             = true
  atomic           = true
  cleanup_on_fail  = true
}

# Deploy additional custom ClusterPolicy resources
resource "kubernetes_manifest" "additional_policies" {
  for_each = var.create ? var.additional_policies : {}

  manifest = yamldecode(each.value)
}
