locals {
  create = var.create
}

resource "aws_route53_record" "delegation" {
  for_each = local.create ? var.delegations : {}

  zone_id = var.parent_zone_id
  name    = each.key
  type    = "NS"
  ttl     = var.ttl
  records = each.value
}
