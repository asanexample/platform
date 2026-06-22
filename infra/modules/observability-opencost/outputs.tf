output "release_name" {
  description = "OpenCost helm release name."
  value       = local.create ? helm_release.opencost[0].name : null
}
