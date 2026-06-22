output "release_name" {
  description = "Helm release name of the events watcher (empty when not created)."
  value       = try(helm_release.events[0].name, "")
}
