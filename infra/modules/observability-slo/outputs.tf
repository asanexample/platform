output "namespace" {
  description = "Namespace the Sloth controller + SLO CRs run in."
  value       = var.namespace
}

output "slo_count" {
  description = "Number of SLOs defined."
  value       = length(var.slos)
}
