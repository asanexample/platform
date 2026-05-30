output "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC identity provider"
  value       = try(aws_iam_openid_connect_provider.github[0].arn, "")
}

output "role_arns" {
  description = "Map of role name to IAM role ARN"
  value       = { for k, r in aws_iam_role.this : k => r.arn }
}

output "role_names" {
  description = "Map of role name to IAM role name"
  value       = { for k, r in aws_iam_role.this : k => r.name }
}

# Diagnostic: the exact OIDC claim patterns each role's trust policy matches. Useful for
# auditing what a role trusts without decoding the rendered assume-role JSON (which embeds
# the OIDC provider ARN and is only known post-apply). Exactly one of these is non-empty
# per scope: `sub` for repo-scoped roles, `job_workflow_ref` for reusable-workflow roles.
output "role_subject_claims" {
  description = "Per-role OIDC `sub` claim patterns the trust policy matches (empty for job_workflow_ref-only roles)."
  value       = local.subject_claims_by_role
}

output "role_job_workflow_ref_claims" {
  description = "Per-role OIDC `job_workflow_ref` claim patterns the trust policy matches (empty for sub-scoped roles)."
  value       = local.job_workflow_ref_claims_by_role
}
