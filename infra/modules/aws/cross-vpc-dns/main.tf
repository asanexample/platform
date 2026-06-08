locals {
  create       = var.create
  use_phz      = local.create && var.dns_method == "phz"
  use_outbound = local.create && var.dns_method == "resolver_outbound"
  use_inbound  = local.create && var.dns_method == "resolver_inbound"

  # PHZ records that use dynamic ENI lookup vs static IPs
  phz_dynamic = { for k, v in var.phz_records : k => v if v.eks_cluster_name != "" && length(v.ips) == 0 }
  phz_static  = { for k, v in var.phz_records : k => v if length(v.ips) > 0 || v.eks_cluster_name == "" }

  phz_resolved_ips = merge(
    { for k, v in local.phz_static : k => v.ips },
    { for k, _ in local.phz_dynamic : k => split(",", data.external.eks_eni_ips[k].result.ips) }
  )
}

# ---------------------------------------------------------------------------
# Dynamic ENI IP lookup via AWS CLI
# ---------------------------------------------------------------------------

# Dynamically look up EKS API ENI IPs via cross-account STS assume-role
data "external" "eks_eni_ips" {
  for_each = local.use_phz ? local.phz_dynamic : {}

  # Hardened: fail LOUDLY on a denied assume-role or an empty result instead of silently writing an empty/stale
  # record (which severs cross-VPC access — e.g. ArgoCD on platform losing the preprod API). The cross-account
  # lookup assumes the target account's role, which only an identity in that role's trust policy can do — run
  # this unit with a profile that can (e.g. `management`); the platform-account profile is NOT trusted by preprod
  # PlatformDeployer and would otherwise fall through to the wrong account and find zero ENIs.
  program = ["bash", "-c", <<-SCRIPT
    set -euo pipefail
    if [ -n "${each.value.eks_lookup_role_arn}" ]; then
      if ! CREDS=$(aws sts assume-role --role-arn "${each.value.eks_lookup_role_arn}" --role-session-name eni-lookup --output json 2>&1); then
        echo "ERROR: assume-role ${each.value.eks_lookup_role_arn} failed: $CREDS" >&2
        echo "Run cross-vpc-dns with a profile that can assume it (e.g. management); the platform profile is NOT in that role's trust policy." >&2
        exit 1
      fi
      AWS_ACCESS_KEY_ID=$(echo "$CREDS" | grep -o '"AccessKeyId": "[^"]*"' | cut -d'"' -f4)
      AWS_SECRET_ACCESS_KEY=$(echo "$CREDS" | grep -o '"SecretAccessKey": "[^"]*"' | cut -d'"' -f4)
      AWS_SESSION_TOKEN=$(echo "$CREDS" | grep -o '"SessionToken": "[^"]*"' | cut -d'"' -f4)
      export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
    fi
    # Region from the EKS endpoint domain (<id>.gr7.<region>.eks.amazonaws.com): with exported assume-role creds
    # the ambient profile's region no longer applies, so pass it explicitly.
    REGION=$(echo "${each.value.domain}" | cut -d. -f3)
    IPS=$(aws ec2 describe-network-interfaces \
      --region "$REGION" \
      --filters "Name=description,Values=Amazon EKS ${each.value.eks_cluster_name}" \
                "Name=status,Values=in-use" \
      --query 'NetworkInterfaces[].PrivateIpAddress' \
      --output text | tr '\t' ',')
    if [ -z "$IPS" ]; then
      echo "ERROR: no in-use ENIs found for EKS cluster '${each.value.eks_cluster_name}' in $REGION." >&2
      echo "Refusing to write an empty PHZ record (would sever cross-VPC access). Verify the cluster is up and the lookup assumed ${each.value.eks_lookup_role_arn} (wrong profile = wrong account = zero ENIs)." >&2
      exit 1
    fi
    echo "{\"ips\": \"$IPS\"}"
  SCRIPT
  ]
}

# ---------------------------------------------------------------------------
# Private Hosted Zones
# ---------------------------------------------------------------------------

resource "aws_route53_zone" "this" {
  for_each = local.use_phz ? var.phz_records : {}

  name = each.value.domain

  vpc {
    vpc_id = var.vpc_id
  }

  tags = merge(var.tags, { Name = "${var.name}-${each.key}" })

  # Additional VPCs may be associated outside Terraform; ignore_changes prevents removing them
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
  records = local.phz_resolved_ips[each.key]
}

# ---------------------------------------------------------------------------
# Resolver Outbound (source VPC)
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# Resolver Inbound (target VPC)
# ---------------------------------------------------------------------------

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
