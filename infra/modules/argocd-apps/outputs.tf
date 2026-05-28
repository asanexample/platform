output "app_projects" {
  description = "Map of tenant names to their ArgoCD AppProject names"
  value       = { for k, v in kubernetes_manifest.app_project : k => v.manifest.metadata.name }
}

output "applications" {
  description = "Map of app keys to their ArgoCD Application names"
  value       = { for k, v in kubernetes_manifest.application : k => v.manifest.metadata.name }
}

output "preview_appsets" {
  description = "Map of app keys to their ArgoCD ApplicationSet names (preview-enabled apps only)"
  value       = { for k, v in kubernetes_manifest.preview_appset : k => v.manifest.metadata.name }
}
