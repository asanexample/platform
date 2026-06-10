output "controller_namespace" {
  description = "Namespace running the ARC controller."
  value       = var.controller_namespace
}

output "runners_namespace" {
  description = "Namespace running the runner scale set + runner pods."
  value       = var.runners_namespace
}

output "runner_scale_set_name" {
  description = "Runner set name — workflows target it via `runs-on: <name>`."
  value       = var.runner_scale_set_name
}

output "github_app_secret" {
  description = "K8s secret (in the runners namespace) holding the projected GitHub App creds."
  value       = local.github_k8s_secret
}
