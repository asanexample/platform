output "release_name" {
  description = "Helm release name of the Alloy log-collector DaemonSet (empty when not created)."
  value       = try(helm_release.alloy[0].name, "")
}
