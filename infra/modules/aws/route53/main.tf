resource "aws_route53_zone" "this" {
  count = var.create ? 1 : 0

  name          = var.domain_name
  comment       = var.comment
  force_destroy = var.force_destroy

  tags = var.tags
}
