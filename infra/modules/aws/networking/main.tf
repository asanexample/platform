locals {
  create = var.create

  public_subnets = local.create ? {
    for k, v in var.subnets : k => v if lookup(v, "public", false)
  } : {}

  private_subnets = local.create ? {
    for k, v in var.subnets : k => v if !lookup(v, "public", false)
  } : {}

  nat_subnets = local.create && var.create_nat_gateways ? (
    var.single_nat_gateway
    ? { for k, v in local.public_subnets : k => v if k == keys(local.public_subnets)[0] }
    : local.public_subnets
  ) : {}

  # Map each private subnet to its NAT gateway (same-AZ preferred, first NAT as fallback)
  private_subnet_nat_map = {
    for k, v in local.private_subnets : k => (
      var.single_nat_gateway
      ? try(keys(local.nat_subnets)[0], null)
      : try(
        [for pk, pv in local.nat_subnets : pk if lookup(pv, "availability_zone", "") == lookup(v, "availability_zone", "no-match")][0],
        try(keys(local.nat_subnets)[0], null)
      )
    )
  }

  configure_eks_sg = local.create && var.enable_eks_networking

  enable_cw_flow_logs = local.create && var.enable_flow_logs && var.flow_log_destination == "cloud-watch-logs"
  enable_s3_flow_logs = local.create && var.enable_flow_logs && var.flow_log_destination == "s3"
}

data "aws_region" "current" {}

# ---------------------------------------------------------------------------
# VPC
# ---------------------------------------------------------------------------

resource "aws_vpc" "this" {
  count = local.create ? 1 : 0

  cidr_block           = var.address_space[0]
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, { Name = var.vpc_name })
}

resource "aws_vpc_ipv4_cidr_block_association" "secondary" {
  for_each = local.create ? {
    for idx, cidr in slice(var.address_space, 1, length(var.address_space)) : idx => cidr
  } : {}

  vpc_id     = aws_vpc.this[0].id
  cidr_block = each.value
}

# ---------------------------------------------------------------------------
# Internet Gateway
# ---------------------------------------------------------------------------

resource "aws_internet_gateway" "this" {
  count = local.create && var.create_internet_gateway ? 1 : 0

  vpc_id = aws_vpc.this[0].id

  tags = merge(var.tags, { Name = "${var.vpc_name}-igw" })
}

# ---------------------------------------------------------------------------
# Subnets
# ---------------------------------------------------------------------------

resource "aws_subnet" "this" {
  for_each = local.create ? var.subnets : {}

  vpc_id            = aws_vpc.this[0].id
  cidr_block        = each.value.address_prefixes[0]
  availability_zone = lookup(each.value, "availability_zone", null)

  map_public_ip_on_launch = lookup(each.value, "public", false)

  tags = merge(
    var.tags,
    { Name = each.key },
    var.enable_eks_networking && can(regex("kubernetes$", each.key)) ? {
      "kubernetes.io/role/internal-elb"                                    = "1"
      "kubernetes.io/cluster/${coalesce(var.eks_cluster_name, "unknown")}" = "shared"
    } : {},
    var.enable_eks_networking && lookup(each.value, "public", false) ? {
      "kubernetes.io/role/elb"                                             = "1"
      "kubernetes.io/cluster/${coalesce(var.eks_cluster_name, "unknown")}" = "shared"
    } : {},
  )
}

# ---------------------------------------------------------------------------
# NAT Gateways
# ---------------------------------------------------------------------------

resource "aws_eip" "nat" {
  for_each = local.nat_subnets

  domain = "vpc"

  tags = merge(var.tags, { Name = "${var.vpc_name}-nat-${each.key}" })
}

resource "aws_nat_gateway" "this" {
  for_each = local.nat_subnets

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.this[each.key].id

  tags = merge(var.tags, { Name = "${var.vpc_name}-nat-${each.key}" })

  depends_on = [aws_internet_gateway.this]
}

# ---------------------------------------------------------------------------
# Route Tables
# ---------------------------------------------------------------------------

resource "aws_route_table" "public" {
  count = local.create && var.create_internet_gateway ? 1 : 0

  vpc_id = aws_vpc.this[0].id

  tags = merge(var.tags, { Name = "${var.vpc_name}-public-rt" })
}

resource "aws_route" "public_internet" {
  count = local.create && var.create_internet_gateway ? 1 : 0

  route_table_id         = aws_route_table.public[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this[0].id
}

resource "aws_route_table_association" "public" {
  for_each = local.create && var.create_internet_gateway ? local.public_subnets : {}

  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.public[0].id
}

resource "aws_route_table" "private" {
  for_each = local.private_subnets

  vpc_id = aws_vpc.this[0].id

  tags = merge(var.tags, { Name = "${var.vpc_name}-private-rt-${each.key}" })
}

resource "aws_route" "private_nat" {
  for_each = {
    for k, v in local.private_subnets : k => v
    if local.private_subnet_nat_map[k] != null && var.create_nat_gateways
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
# S3 Gateway Endpoint (free — reduces NAT costs for S3 traffic)
# ---------------------------------------------------------------------------

resource "aws_vpc_endpoint" "s3" {
  count = local.create ? 1 : 0

  vpc_id            = aws_vpc.this[0].id
  service_name      = "com.amazonaws.${data.aws_region.current.id}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = compact(concat(
    var.create_internet_gateway ? [aws_route_table.public[0].id] : [],
    [for k, v in aws_route_table.private : v.id],
  ))

  tags = merge(var.tags, { Name = "${var.vpc_name}-s3-endpoint" })
}

# ---------------------------------------------------------------------------
# Interface VPC Endpoints (Secrets Manager, SSM, STS, KMS, etc.)
# ---------------------------------------------------------------------------

resource "aws_security_group" "vpc_endpoints" {
  count = local.create && length(var.interface_vpc_endpoints) > 0 ? 1 : 0

  name_prefix = "${var.vpc_name}-vpce-"
  description = "Allow HTTPS from VPC to interface endpoints"
  vpc_id      = aws_vpc.this[0].id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.address_space
    description = "HTTPS from VPC"
  }

  tags = merge(var.tags, { Name = "${var.vpc_name}-vpce-sg" })
}

resource "aws_vpc_endpoint" "interface" {
  for_each = local.create ? toset(var.interface_vpc_endpoints) : toset([])

  vpc_id              = aws_vpc.this[0].id
  service_name        = "com.amazonaws.${data.aws_region.current.id}.${each.value}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = [for k, v in local.private_subnets : aws_subnet.this[k].id]
  security_group_ids = [aws_security_group.vpc_endpoints[0].id]

  tags = merge(var.tags, { Name = "${var.vpc_name}-${each.value}-endpoint" })
}

# ---------------------------------------------------------------------------
# EKS Security Group
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# VPC Flow Logs
# ---------------------------------------------------------------------------

resource "aws_flow_log" "this" {
  count = local.create && var.enable_flow_logs ? 1 : 0

  vpc_id               = aws_vpc.this[0].id
  traffic_type         = "ALL"
  log_destination_type = var.flow_log_destination
  log_destination      = var.flow_log_destination == "s3" ? var.flow_log_s3_bucket_arn : aws_cloudwatch_log_group.flow_log[0].arn
  iam_role_arn         = var.flow_log_destination == "cloud-watch-logs" ? aws_iam_role.flow_log[0].arn : null

  tags = merge(var.tags, { Name = "${var.vpc_name}-flow-log" })
}

resource "aws_cloudwatch_log_group" "flow_log" {
  count = local.enable_cw_flow_logs ? 1 : 0

  name              = "/aws/vpc/flow-log/${var.vpc_name}"
  retention_in_days = var.flow_log_retention_days

  tags = var.tags
}

resource "aws_iam_role" "flow_log" {
  count = local.enable_cw_flow_logs ? 1 : 0

  name_prefix = "${var.vpc_name}-flow-log-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "flow_log" {
  count = local.enable_cw_flow_logs ? 1 : 0

  name_prefix = "flow-log-"
  role        = aws_iam_role.flow_log[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
      ]
      Resource = "*"
    }]
  })
}
