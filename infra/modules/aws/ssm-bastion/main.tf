locals {
  create = var.create
}

data "aws_ssm_parameter" "al2023" {
  count = local.create ? 1 : 0

  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

# ---------------------------------------------------------------------------
# IAM — Instance Profile with SSM
# ---------------------------------------------------------------------------

resource "aws_iam_role" "bastion" {
  count = local.create ? 1 : 0

  name_prefix = "${var.name}-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  count = local.create ? 1 : 0

  role       = aws_iam_role.bastion[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "bastion" {
  count = local.create ? 1 : 0

  name_prefix = "${var.name}-"
  role        = aws_iam_role.bastion[0].name

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Security Group — egress only, no inbound
# ---------------------------------------------------------------------------

resource "aws_security_group" "bastion" {
  count = local.create ? 1 : 0

  name_prefix = "${var.name}-"
  description = "SSM bastion - egress only"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = var.name })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_egress_rule" "https" {
  count = local.create ? 1 : 0

  security_group_id = aws_security_group.bastion[0].id
  description       = "HTTPS for SSM and EKS API"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"

  tags = var.tags
}

# ---------------------------------------------------------------------------
# EC2 Instance
# ---------------------------------------------------------------------------

resource "aws_instance" "bastion" {
  count = local.create ? 1 : 0

  ami                  = data.aws_ssm_parameter.al2023[0].value
  instance_type        = var.instance_type
  subnet_id            = var.subnet_id
  iam_instance_profile = aws_iam_instance_profile.bastion[0].name

  vpc_security_group_ids = [aws_security_group.bastion[0].id]

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_size = 8
    encrypted   = true
  }

  tags = merge(var.tags, { Name = var.name })
}
