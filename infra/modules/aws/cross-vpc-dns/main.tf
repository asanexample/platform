locals {
  create       = var.create
  use_phz      = local.create && var.dns_method == "phz"
  use_outbound = local.create && var.dns_method == "resolver_outbound"
  use_inbound  = local.create && var.dns_method == "resolver_inbound"
}

# ── PHZ ──────────────────────────────────────────────────────────────────

resource "aws_route53_zone" "this" {
  for_each = local.use_phz ? var.phz_records : {}

  name = each.value.domain

  vpc {
    vpc_id = var.vpc_id
  }

  tags = merge(var.tags, { Name = "${var.name}-${each.key}" })

  lifecycle {
    ignore_changes = [vpc]
  }
}

resource "aws_route53_record" "this" {
  for_each = local.use_phz ? var.phz_records : {}

  zone_id = aws_route53_zone.this[each.key].zone_id
  name    = each.value.domain
  type    = "A"
  ttl     = each.value.ttl
  records = each.value.ips
}

# ── Resolver Outbound (source VPC) ──────────────────────────────────────

resource "aws_security_group" "resolver_outbound" {
  count = local.use_outbound ? 1 : 0

  name_prefix = "${var.name}-resolver-out-"
  description = "Route53 Resolver outbound endpoint"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-resolver-out" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "resolver_outbound_egress_udp" {
  count = local.use_outbound ? 1 : 0

  security_group_id = aws_security_group.resolver_outbound[0].id
  type              = "egress"
  from_port         = 53
  to_port           = 53
  protocol          = "udp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "DNS UDP outbound"
}

resource "aws_security_group_rule" "resolver_outbound_egress_tcp" {
  count = local.use_outbound ? 1 : 0

  security_group_id = aws_security_group.resolver_outbound[0].id
  type              = "egress"
  from_port         = 53
  to_port           = 53
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "DNS TCP outbound"
}

resource "aws_route53_resolver_endpoint" "outbound" {
  count = local.use_outbound ? 1 : 0

  name      = "${var.name}-outbound"
  direction = "OUTBOUND"

  security_group_ids = [aws_security_group.resolver_outbound[0].id]

  dynamic "ip_address" {
    for_each = var.resolver_subnet_ids
    content {
      subnet_id = ip_address.value
    }
  }

  tags = merge(var.tags, { Name = "${var.name}-outbound" })
}

resource "aws_route53_resolver_rule" "this" {
  for_each = local.use_outbound ? var.forwarding_rules : {}

  name                 = "${var.name}-${each.key}"
  domain_name          = each.value.domain
  rule_type            = "FORWARD"
  resolver_endpoint_id = aws_route53_resolver_endpoint.outbound[0].id

  dynamic "target_ip" {
    for_each = each.value.target_ips
    content {
      ip = target_ip.value
    }
  }

  tags = merge(var.tags, { Name = "${var.name}-${each.key}" })
}

resource "aws_route53_resolver_rule_association" "this" {
  for_each = local.use_outbound ? var.forwarding_rules : {}

  resolver_rule_id = aws_route53_resolver_rule.this[each.key].id
  vpc_id           = var.vpc_id
}

# ── Resolver Inbound (target VPC) ───────────────────────────────────────

resource "aws_security_group" "resolver_inbound" {
  count = local.use_inbound ? 1 : 0

  name_prefix = "${var.name}-resolver-in-"
  description = "Route53 Resolver inbound endpoint"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-resolver-in" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "resolver_inbound_ingress_udp" {
  count = local.use_inbound ? 1 : 0

  security_group_id = aws_security_group.resolver_inbound[0].id
  type              = "ingress"
  from_port         = 53
  to_port           = 53
  protocol          = "udp"
  cidr_blocks       = var.resolver_allowed_cidrs
  description       = "DNS UDP from source VPC"
}

resource "aws_security_group_rule" "resolver_inbound_ingress_tcp" {
  count = local.use_inbound ? 1 : 0

  security_group_id = aws_security_group.resolver_inbound[0].id
  type              = "ingress"
  from_port         = 53
  to_port           = 53
  protocol          = "tcp"
  cidr_blocks       = var.resolver_allowed_cidrs
  description       = "DNS TCP from source VPC"
}

resource "aws_route53_resolver_endpoint" "inbound" {
  count = local.use_inbound ? 1 : 0

  name      = "${var.name}-inbound"
  direction = "INBOUND"

  security_group_ids = [aws_security_group.resolver_inbound[0].id]

  dynamic "ip_address" {
    for_each = var.resolver_subnet_ids
    content {
      subnet_id = ip_address.value
    }
  }

  tags = merge(var.tags, { Name = "${var.name}-inbound" })
}
