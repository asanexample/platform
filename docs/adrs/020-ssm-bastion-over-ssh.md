# ADR-020: SSM Session Manager Bastion over SSH Bastion

**Date:** 2026-05-23

**Status:** Accepted

## Context

The platform's EKS cluster runs in private subnets with a private-only API endpoint (ADR-010).
Before Tailscale was deployed (ADR-011), a bastion host was needed to provide access to VPC
resources — primarily the EKS API server via port forwarding, but also for ad-hoc debugging of
VPC networking, DNS resolution, and security group behavior.

Traditional bastion hosts use SSH: an EC2 instance in a public subnet with port 22 open, accessed
via SSH key pairs. This model has well-known operational problems:

1. **Key management.** SSH key pairs must be generated, distributed to authorized users, rotated
   periodically, and revoked when engineers leave. Lost or leaked keys provide direct access to
   the bastion.

2. **Network exposure.** Port 22 must be open in a security group, creating a persistent
   internet-facing attack surface. Even with IP allowlisting, the port is visible to network
   scanners.

3. **Audit logging.** SSH session logging requires additional tooling (auditd, session recording).
   There's no built-in integration with AWS CloudTrail or centralized logging.

4. **Public subnet requirement.** The bastion must be in a public subnet with an Elastic IP or
   public IP, consuming limited public subnet address space.

### Alternatives Considered

**1. Traditional SSH bastion in public subnet.** Standard approach. Place an EC2 instance in a
public subnet, open port 22, distribute SSH keys. Well-understood, works with any SSH client.
Rejected due to key management burden, network exposure, and lack of native audit integration.

**2. EC2 Instance Connect.** AWS service that pushes temporary SSH keys to the instance metadata,
eliminating long-lived key management. Still requires port 22 open in a security group and a
public IP (unless using Instance Connect Endpoint, which is newer and has per-VPC limits).
Better than traditional SSH but still network-exposed.

**3. AWS Systems Manager Session Manager (chosen).** SSM provides a shell session to EC2 instances
through the SSM agent, which communicates outbound to the SSM service endpoint via HTTPS (port
443). No inbound ports, no SSH keys, no public IP. Access is controlled via IAM policies.
Sessions are logged to CloudTrail with optional session recording to S3 or CloudWatch Logs.

## Decision

Deploy a minimal EC2 instance (`t3.nano`) in a private subnet with SSM Session Manager as the
sole access mechanism. No SSH, no public IP, no inbound security group rules.

### Implementation

The `ssm-bastion` module (`infra/modules/aws/ssm-bastion/`) creates:

1. **IAM role** with `AmazonSSMManagedInstanceCore` managed policy — grants the instance
   permission to communicate with the SSM service
2. **Security group** with egress-only rules — no inbound rules at all. Outbound traffic to the
   VPC allows the bastion to reach the EKS API endpoint and other private resources.
3. **EC2 instance** running Amazon Linux 2023 (latest AMI from SSM parameter), in a private subnet

```hcl
resource "aws_security_group" "bastion" {
  name_prefix = "${var.name}-"
  description = "SSM bastion - egress only"
  vpc_id      = var.vpc_id
}
```

### EKS Integration

When `cluster_security_group_id` is provided, the module adds an ingress rule to the EKS cluster
security group allowing HTTPS (443) from the bastion's security group. This lets the bastion
forward traffic to the EKS API endpoint for the SSM tunnel script.

### Port Forwarding

The `scripts/eks-tunnel.sh` script uses SSM's port forwarding feature to create a local tunnel to
the EKS API endpoint:

```bash
aws ssm start-session \
  --target <instance-id> \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "host=<eks-endpoint>,portNumber=443,localPortNumber=8443"
```

### Instance Sizing

The bastion is a `t3.nano` (2 vCPU, 0.5 GiB RAM, ~$3.80/month). It serves only as a network
relay for SSM sessions — no workloads run on it. The SSM agent has minimal resource requirements.

## Consequences

**Positive:**

- Zero inbound attack surface — no open ports, no public IP, no SSH keys to manage or rotate
- IAM-based access control — who can start SSM sessions is governed by IAM policies, integrated
  with Identity Center and the role model (ADR-007)
- Native audit trail — every session start/stop is logged in CloudTrail. Session recording
  (optional) captures full terminal I/O.
- Private subnet placement — no public subnet or Elastic IP needed, reducing cost and exposure
- Minimal resource footprint — t3.nano at ~$3.80/month

**Negative:**

- SSM sessions have higher latency than direct SSH — traffic routes through the SSM service
  endpoint rather than a direct TCP connection
- Requires AWS CLI v2 and the Session Manager plugin installed on developer machines
- Port forwarding through SSM is less ergonomic than direct SSH tunnels — each tunnel requires
  a separate `aws ssm start-session` command
- The bastion instance must be running for SSM sessions to work — if it's stopped or terminated,
  SSM access is unavailable until it's restarted

**Risks:**

- If the SSM service itself has an outage, bastion access is unavailable. This is an AWS
  service dependency. Mitigated by SSM being a core AWS service with high availability, and
  Tailscale providing an independent access path (ADR-011).
- The bastion's IAM role has `AmazonSSMManagedInstanceCore`, which includes permissions to
  communicate with SSM, CloudWatch, and S3. This is broader than strictly necessary for a tunnel
  relay. Mitigated by the instance having no inbound access and the security group blocking
  inbound traffic.
