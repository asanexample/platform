output "record_ids" {
  description = "Map of nameserver to Cloudflare DNS record ID"
  value       = { for ns, record in cloudflare_dns_record.ns : ns => record.id }
}
