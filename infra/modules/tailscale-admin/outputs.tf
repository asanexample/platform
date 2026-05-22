output "acl_id" {
  description = "The ACL resource ID"
  value       = try(tailscale_acl.this[0].id, null)
}

output "split_dns_domains" {
  description = "List of configured split DNS domains"
  value       = keys(tailscale_dns_split_nameservers.this)
}

output "oauth_client_id" {
  description = "OAuth client ID for the K8s operator"
  value       = try(tailscale_oauth_client.k8s_operator[0].id, null)
  sensitive   = true
}

output "oauth_secret_arn" {
  description = "ARN of the Secrets Manager secret containing OAuth credentials"
  value       = try(aws_secretsmanager_secret.oauth[0].arn, null)
}
