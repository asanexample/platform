resource "aws_route53_zone" "this" {
  count = var.create ? 1 : 0

  name          = var.domain_name
  comment       = var.comment
  force_destroy = var.force_destroy

  tags = var.tags
}

resource "aws_route53_record" "caa" {
  count = var.create && length(var.caa_records) > 0 ? 1 : 0

  zone_id = aws_route53_zone.this[0].zone_id
  name    = var.domain_name
  type    = "CAA"
  ttl     = 3600 # 1-hour TTL for CAA records
  records = var.caa_records
}
