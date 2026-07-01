output "release_name" {
  description = "policy-reporter helm release name."
  value       = local.create ? helm_release.policy_reporter[0].name : null
}
