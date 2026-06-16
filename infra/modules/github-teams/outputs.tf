output "team_slugs" {
  description = "Managed team name -> GitHub team slug."
  value       = { for k, t in github_team.this : k => t.slug }
}

output "team_ids" {
  description = "Managed team name -> GitHub team id."
  value       = { for k, t in github_team.this : k => t.id }
}
