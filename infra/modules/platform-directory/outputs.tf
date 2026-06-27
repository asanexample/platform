output "namespace" {
  description = "The directory DB namespace."
  value       = var.namespace
}

output "db_secret_name" {
  description = "Secrets Manager name holding the directory Postgres connection string (uri)."
  value       = var.db_secret_name
}
