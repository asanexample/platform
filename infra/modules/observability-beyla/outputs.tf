output "release_name" {
  description = "Beyla helm release name."
  value       = local.create ? helm_release.beyla[0].name : null
}
