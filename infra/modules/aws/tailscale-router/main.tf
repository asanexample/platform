locals {
  create = var.create

  user_data = local.create ? base64encode(templatefile("${path.module}/user-data.sh.tftpl", {
    auth_secret_id   = var.auth_secret_id
    region           = var.region
    advertise_routes = join(",", var.advertise_routes)
    advertise_tags   = join(",", var.advertise_tags)
    hostname         = var.name
  })) : null
}

# Latest Amazon Linux 2023 arm64 AMI (Graviton)
data "aws_ssm_parameter" "al2023_arm64" {
  count = local.create ? 1 : 0

  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

# Resolve the auth secret's ARN so the instance policy can be scoped to exactly it
data "aws_secretsmanager_secret" "auth" {
  count = local.create ? 1 : 0

  name = var.auth_secret_id
}

# ---------------------------------------------------------------------------
# IAM — Instance Profile: SSM (patch/debug) + read the Tailscale auth secret
# ---------------------------------------------------------------------------

resource "aws_iam_role" "router" {
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

  role       = aws_iam_role.router[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "read_auth_secret" {
  count = local.create ? 1 : 0

  name = "read-tailscale-auth"
  role = aws_iam_role.router[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = data.aws_secretsmanager_secret.auth[0].arn
    }]
  })
}

resource "aws_iam_instance_profile" "router" {
  count = local.create ? 1 : 0

  name_prefix = "${var.name}-"
  role        = aws_iam_role.router[0].name

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Security Group — egress only (Tailscale + forwarded subnet traffic), no inbound
# ---------------------------------------------------------------------------

resource "aws_security_group" "router" {
  count = local.create ? 1 : 0

  name_prefix = "${var.name}-"
  description = "Tailscale subnet router - egress only"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = var.name })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_egress_rule" "https" {
  count = local.create ? 1 : 0

  security_group_id = aws_security_group.router[0].id
  description       = "HTTPS: Tailscale control plane, DERP relays, SSM, AWS APIs, package repos"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"

  tags = var.tags
}

resource "aws_vpc_security_group_egress_rule" "stun" {
  count = local.create ? 1 : 0

  security_group_id = aws_security_group.router[0].id
  description       = "UDP STUN for Tailscale NAT traversal"
  ip_protocol       = "udp"
  from_port         = 3478
  to_port           = 3478
  cidr_ipv4         = "0.0.0.0/0"

  tags = var.tags
}

resource "aws_vpc_security_group_egress_rule" "wireguard" {
  count = local.create ? 1 : 0

  security_group_id = aws_security_group.router[0].id
  description       = "UDP WireGuard direct connections for Tailscale"
  ip_protocol       = "udp"
  from_port         = 41641
  to_port           = 41641
  cidr_ipv4         = "0.0.0.0/0"

  tags = var.tags
}

# Forwarded subnet-route traffic (tailnet client -> router -> in-VPC target, any port)
resource "aws_vpc_security_group_egress_rule" "advertised_routes" {
  for_each = local.create ? toset(var.advertise_routes) : toset([])

  security_group_id = aws_security_group.router[0].id
  description       = "All traffic to advertised subnet-route target ${each.value}"
  ip_protocol       = "-1"
  cidr_ipv4         = each.value

  tags = var.tags
}

# ---------------------------------------------------------------------------
# EC2 Instance — the subnet router
# ---------------------------------------------------------------------------

resource "aws_instance" "router" {
  count = local.create ? 1 : 0

  ami                    = data.aws_ssm_parameter.al2023_arm64[0].value
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  iam_instance_profile   = aws_iam_instance_profile.router[0].name
  vpc_security_group_ids = [aws_security_group.router[0].id]

  # A subnet router forwards packets whose source/destination is not its own IP.
  source_dest_check = false

  user_data_base64            = local.user_data
  user_data_replace_on_change = true

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_size = 8 # Stateless router — only the OS, tailscaled, and awscli
    encrypted   = true
  }

  tags = merge(var.tags, { Name = var.name })
}
