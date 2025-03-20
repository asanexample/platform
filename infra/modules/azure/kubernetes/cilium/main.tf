/**
 * # Cilium CNI Installation Module
 *
 * This module previously installed Cilium CNI using the Helm provider on an AKS cluster.
 * It has been modified to remove the Helm chart installation as requested.
 * Cilium installation will be handled outside of Terragrunt/Terraform.
 */

# Time sleep to allow the kubernetes API to settle after cluster creation
resource "time_sleep" "wait_for_kubernetes" {
  depends_on = [var.module_depends_on]
  create_duration = "30s"
}

# Local value to indicate Cilium installation has been removed
locals {
  cilium_message = "Cilium installation has been removed from Terraform management. It will be managed externally."
}

# Output message for clarity
output "message" {
  value = local.cilium_message
}

output "cilium_namespace" {
  value = var.namespace
  description = "The namespace where Cilium would be installed"
} 