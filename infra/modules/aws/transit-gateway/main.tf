locals {
  create     = var.create
  create_tgw = local.create && var.create_tgw
  tgw_id     = local.create_tgw ? aws_ec2_transit_gateway.this[0].id : var.transit_gateway_id

  # Create a route for every (route_table x destination_cidr) combination
  route_pairs = {
    for pair in setproduct(keys(var.route_table_ids), var.destination_cidrs) :
    "${pair[0]}:${pair[1]}" => {
      route_table_id = var.route_table_ids[pair[0]]
      cidr           = pair[1]
    }
  }
}

# ---------------------------------------------------------------------------
# Transit Gateway (hub)
# ---------------------------------------------------------------------------

resource "aws_ec2_transit_gateway" "this" {
  count = local.create_tgw ? 1 : 0

  amazon_side_asn = var.amazon_side_asn
  # Spoke VPCs attach without manual approval (trusted accounts only)
  auto_accept_shared_attachments  = "enable"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"

  tags = merge(var.tags, { Name = var.name })
}

# ---------------------------------------------------------------------------
# RAM Share (hub)
# ---------------------------------------------------------------------------

resource "aws_ram_resource_share" "this" {
  count = local.create_tgw && length(var.ram_share_principals) > 0 ? 1 : 0

  name = "${var.name}-share"
  # Required for cross-account sharing; could be false if RAM org sharing is enabled
  allow_external_principals = true

  tags = merge(var.tags, { Name = "${var.name}-share" })
}

resource "aws_ram_resource_association" "this" {
  count = local.create_tgw && length(var.ram_share_principals) > 0 ? 1 : 0

  resource_share_arn = aws_ram_resource_share.this[0].arn
  resource_arn       = aws_ec2_transit_gateway.this[0].arn
}

resource "aws_ram_principal_association" "this" {
  for_each = local.create_tgw ? toset(var.ram_share_principals) : toset([])

  resource_share_arn = aws_ram_resource_share.this[0].arn
  principal          = each.value
}

# ---------------------------------------------------------------------------
# RAM Share Acceptance (spoke)
# ---------------------------------------------------------------------------

resource "aws_ram_resource_share_accepter" "this" {
  count = local.create && !var.create_tgw && var.ram_share_arn != null ? 1 : 0

  share_arn = var.ram_share_arn
}

# ---------------------------------------------------------------------------
# VPC Attachment
# ---------------------------------------------------------------------------

resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  count = local.create ? 1 : 0

  transit_gateway_id = local.tgw_id
  vpc_id             = var.vpc_id
  subnet_ids         = var.subnet_ids
  dns_support        = "enable"

  tags = merge(var.tags, { Name = "${var.name}-attachment" })

  depends_on = [
    aws_ram_resource_share_accepter.this,
    aws_ram_principal_association.this,
  ]
}

# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

resource "aws_route" "tgw" {
  for_each = local.create ? local.route_pairs : {}

  route_table_id         = each.value.route_table_id
  destination_cidr_block = each.value.cidr
  transit_gateway_id     = local.tgw_id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.this]
}

# ---------------------------------------------------------------------------
# Security Group Rules (spoke, optional)
# ---------------------------------------------------------------------------

resource "aws_security_group_rule" "tgw_ingress" {
  for_each = local.create && var.security_group_id != null ? toset(var.security_group_ingress_cidrs) : toset([])

  security_group_id = var.security_group_id
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = [each.value]
  description       = "TGW: HTTPS from ${each.value}"
}
