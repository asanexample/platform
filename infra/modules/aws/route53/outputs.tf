output "zone_id" {
  description = "The hosted zone ID"
  value       = var.create ? aws_route53_zone.this[0].zone_id : null
}

output "zone_name" {
  description = "The hosted zone name"
  value       = var.create ? aws_route53_zone.this[0].name : null
}

output "name_servers" {
  description = "Name servers for the hosted zone (add these as NS records in your registrar)"
  value       = var.create ? aws_route53_zone.this[0].name_servers : []
}

output "zone_arn" {
  description = "The hosted zone ARN"
  value       = var.create ? aws_route53_zone.this[0].arn : null
}
