resource "cloudflare_dns_record" "ns" {
  for_each = var.create ? toset(var.nameservers) : toset([])

  zone_id = var.cloudflare_zone_id
  name    = var.subdomain
  type    = "NS"
  content = each.value
  ttl     = 3600
}
