/**
 * Outputs for the Cilium CNI Installation Module
 */

output "release_name" {
  description = "Name of the Helm release"
  value       = helm_release.cilium.name
}

output "release_namespace" {
  description = "Namespace of the Helm release"
  value       = helm_release.cilium.namespace
}

output "release_status" {
  description = "Status of the Helm release"
  value       = helm_release.cilium.status
}

output "release_version" {
  description = "Version of the Helm release"
  value       = helm_release.cilium.version
} 