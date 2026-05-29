output "delegation_records" {
  description = "Map of delegated subdomains to their NS records"
  value       = { for k, v in aws_route53_record.delegation : k => v.records }
}
