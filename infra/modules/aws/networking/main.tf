/**
 * # AWS Networking Module
 *
 * This module creates an AWS VPC with subnets, internet gateway, NAT gateways,
 * and route tables. It also supports EKS-specific networking features when enabled.
 *
 * Cross-cloud interface: This module exposes the same logical outputs as the
 * Azure networking module (network_id, subnet_ids, etc.) to support the
 * multi-cloud abstraction pattern.
 */

# ---------------------------------------------------------------------------
# VPC
# ---------------------------------------------------------------------------

resource "aws_vpc" "this" {
  count = var.create ? 1 : 0

  cidr_block           = var.address_space[0]
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, { Name = var.vpc_name })
}

# Secondary CIDR blocks (if more than one address_space entry is provided)
resource "aws_vpc_ipv4_cidr_block_association" "secondary" {
  for_each = var.create ? {
    for idx, cidr in slice(var.address_space, 1, length(var.address_space)) : idx => cidr
  } : {}

  vpc_id     = aws_vpc.this[0].id
  cidr_block = each.value
}

# ---------------------------------------------------------------------------
# Internet Gateway
# ---------------------------------------------------------------------------

resource "aws_internet_gateway" "this" {
  count = var.create ? 1 : 0

  vpc_id = aws_vpc.this[0].id

  tags = merge(var.tags, { Name = "${var.vpc_name}-igw" })
}

# ---------------------------------------------------------------------------
# Subnets
# ---------------------------------------------------------------------------

resource "aws_subnet" "this" {
  for_each = var.create ? var.subnets : {}

  vpc_id            = aws_vpc.this[0].id
  cidr_block        = each.value.address_prefixes[0]
  availability_zone = lookup(each.value, "availability_zone", null)

  map_public_ip_on_launch = lookup(each.value, "public", false)

  tags = merge(
    var.tags,
    { Name = each.key },
    # Tag kubernetes subnets for EKS auto-discovery when enabled
    var.enable_eks_networking && can(regex("kubernetes$", each.key)) ? {
      "kubernetes.io/role/internal-elb"                        = "1"
      "kubernetes.io/cluster/${coalesce(var.eks_cluster_name, "unknown")}" = "shared"
    } : {},
    var.enable_eks_networking && lookup(each.value, "public", false) ? {
      "kubernetes.io/role/elb"                                 = "1"
      "kubernetes.io/cluster/${coalesce(var.eks_cluster_name, "unknown")}" = "shared"
    } : {},
  )
}

# ---------------------------------------------------------------------------
# Elastic IPs for NAT Gateways
# ---------------------------------------------------------------------------

# One NAT gateway per AZ that has a public subnet
locals {
  public_subnets = var.create ? {
    for k, v in var.subnets : k => v if lookup(v, "public", false)
  } : {}
}

resource "aws_eip" "nat" {
  for_each = local.public_subnets

  domain = "vpc"

  tags = merge(var.tags, { Name = "${var.vpc_name}-nat-${each.key}" })
}

# ---------------------------------------------------------------------------
# NAT Gateways (one per public subnet)
# ---------------------------------------------------------------------------

resource "aws_nat_gateway" "this" {
  for_each = local.public_subnets

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.this[each.key].id

  tags = merge(var.tags, { Name = "${var.vpc_name}-nat-${each.key}" })

  depends_on = [aws_internet_gateway.this]
}

# ---------------------------------------------------------------------------
# Route Tables
# ---------------------------------------------------------------------------

# Public route table — routes internet traffic through the IGW
resource "aws_route_table" "public" {
  count = var.create ? 1 : 0

  vpc_id = aws_vpc.this[0].id

  tags = merge(var.tags, { Name = "${var.vpc_name}-public-rt" })
}

resource "aws_route" "public_internet" {
  count = var.create ? 1 : 0

  route_table_id         = aws_route_table.public[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this[0].id
}

# Associate public subnets with the public route table
resource "aws_route_table_association" "public" {
  for_each = local.public_subnets

  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.public[0].id
}

# Private route tables — one per AZ, routing through the NAT gateway in that AZ
locals {
  private_subnets = var.create ? {
    for k, v in var.subnets : k => v if !lookup(v, "public", false)
  } : {}

  # Map each private subnet to its nearest public subnet (same AZ) for NAT routing
  # Falls back to the first public subnet if no AZ match is found
  private_subnet_nat_map = {
    for k, v in local.private_subnets : k => try(
      [for pk, pv in local.public_subnets : pk if lookup(pv, "availability_zone", "") == lookup(v, "availability_zone", "no-match")][0],
      try(keys(local.public_subnets)[0], null)
    )
  }
}

resource "aws_route_table" "private" {
  for_each = local.private_subnets

  vpc_id = aws_vpc.this[0].id

  tags = merge(var.tags, { Name = "${var.vpc_name}-private-rt-${each.key}" })
}

resource "aws_route" "private_nat" {
  for_each = {
    for k, v in local.private_subnets : k => v
    if local.private_subnet_nat_map[k] != null
  }

  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[local.private_subnet_nat_map[each.key]].id
}

resource "aws_route_table_association" "private" {
  for_each = local.private_subnets

  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.private[each.key].id
}

# ---------------------------------------------------------------------------
# EKS Networking — Security Group
# ---------------------------------------------------------------------------

locals {
  configure_eks_sg = var.create && var.enable_eks_networking
}

resource "aws_security_group" "eks" {
  count = local.configure_eks_sg ? 1 : 0

  name_prefix = "${coalesce(var.eks_cluster_name, var.vpc_name)}-eks-"
  description = "Security group for EKS cluster networking"
  vpc_id      = aws_vpc.this[0].id

  tags = merge(var.tags, { Name = "${coalesce(var.eks_cluster_name, var.vpc_name)}-eks-sg" })
}

resource "aws_security_group_rule" "eks_self" {
  count = local.configure_eks_sg ? 1 : 0

  security_group_id = aws_security_group.eks[0].id
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  self              = true
  description       = "Allow all traffic within the EKS security group"
}

resource "aws_security_group_rule" "eks_egress" {
  count = local.configure_eks_sg ? 1 : 0

  security_group_id = aws_security_group.eks[0].id
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow all outbound traffic"
}
