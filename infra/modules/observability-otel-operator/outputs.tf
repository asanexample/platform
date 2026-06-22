output "instrumentation_ref" {
  description = "Reference apps put in the inject annotation: instrumentation.opentelemetry.io/inject-<lang>."
  value       = local.create ? "${var.namespace}/${var.instrumentation_name}" : null
}
