output "release_name" {
  description = "Name of the prometheus-operator-crds Helm release (a dependency anchor for units that create ServiceMonitors/PrometheusRules)"
  value       = local.create ? helm_release.crds[0].name : null
}
