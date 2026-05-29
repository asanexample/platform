/**
 * # vCluster Module Outputs
 */

output "name" {
  description = "Name of the vCluster instance"
  value       = var.create ? helm_release.vcluster[0].name : var.cluster_name
}

output "namespace" {
  description = "Kubernetes namespace where the vCluster is deployed"
  value       = var.create ? helm_release.vcluster[0].namespace : var.namespace
}

output "helm_release_name" {
  description = "Name of the vCluster Helm release"
  value       = var.create ? helm_release.vcluster[0].name : var.cluster_name
}

output "helm_release_status" {
  description = "Status of the vCluster Helm release"
  value       = var.create ? helm_release.vcluster[0].status : "disabled"
}

output "kubeconfig_secret_name" {
  description = "Name of the K8s secret containing the vCluster kubeconfig"
  value       = var.create ? "vc-${var.cluster_name}" : null
}
