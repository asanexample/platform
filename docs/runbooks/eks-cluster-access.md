# Runbook: EKS Cluster Access

> **Roles:** PlatformAdmin, PlatformDeployer, DeveloperAccess
> **Related ADR:** [007-iam-role-model](../adrs/007-iam-role-model.md)
> **See also:** [ArgoCD SSO](argocd-sso.md) for web UI access
>
> **Last reviewed:** 2026-05-28

---

## Table of Contents

1. [Tailscale VPN Access (Recommended)](#tailscale-vpn-access-recommended)
2. [Platform Engineer: kubectl Setup](#platform-engineer-kubectl-setup)
3. [Developer: Namespace-Scoped kubectl](#developer-namespace-scoped-kubectl)
4. [Private Cluster Access via SSM Tunnel](#private-cluster-access-via-ssm-tunnel)
5. [Break-Glass Access](#break-glass-access)
6. [Troubleshooting](#troubleshooting)

---

## Tailscale VPN Access (Recommended)

Tailscale provides always-on mesh VPN access to the private EKS cluster.
No tunnel management required -- once connected, kubectl works directly.

> **Full details:** [Tailscale VPN Runbook](tailscale-vpn.md) (setup from
> scratch, rebuild procedures, troubleshooting, architecture)

### One-Time Setup

1. Install Tailscale: <https://tailscale.com/download>
1. Get a tailnet invite from the platform team
1. Configure kubeconfig:

```bash
aws sso login --profile platform

AWS_PROFILE=platform aws eks update-kubeconfig \
  --name platform-use1-eks \
  --region us-east-1 \
  --role-arn arn:aws:iam::829808296602:role/PlatformAdmin
```

1. Verify: `kubectl get nodes`

### Fallback

If Tailscale is unavailable, use the [SSM tunnel](#private-cluster-access-via-ssm-tunnel).

---

## Platform Engineer: kubectl Setup

Platform engineers use the **PlatformAdmin** role for cluster access.

### Prerequisites

- AWS CLI v2 with SSO configured
- kubectl installed
- An SSO profile for the platform account (see AWS config below)

### AWS Config

Add to `~/.aws/config`:

```ini
[profile platform]
sso_session = centric
sso_account_id = 829808296602
sso_role_name = AdministratorAccess

[sso-session centric]
sso_start_url = https://d-9067aa6520.awsapps.com/start
sso_region = us-east-1
sso_registration_scopes = sso:account:access
```

### Steps

```bash
# 1. Log in via SSO
aws sso login --profile platform

# 2. Configure kubeconfig (one-time, persists across sessions)
AWS_PROFILE=platform aws eks update-kubeconfig \
  --name platform-use1-eks \
  --region us-east-1 \
  --role-arn arn:aws:iam::829808296602:role/PlatformAdmin

# 3. Verify access
kubectl get pods -A
```

The `--role-arn` flag embeds the PlatformAdmin role in the kubeconfig, so
subsequent `kubectl` commands automatically assume it.

---

## Developer: Namespace-Scoped kubectl

Developers use the **DeveloperAccess** role on the **preprod** cluster, which
grants access only to assigned team namespaces. The platform cluster does not
have developer access -- it is admin-only.

### Prerequisites

- AWS CLI v2 with SSO configured
- kubectl installed
- Namespace assignment in the EKS access entry (managed by platform team)

### AWS Config

Add to `~/.aws/config`:

```ini
[profile preprod-dev]
sso_session = centric
sso_account_id = 620830101009
sso_role_name = PowerUserAccess

[sso-session centric]
sso_start_url = https://d-9067aa6520.awsapps.com/start
sso_region = us-east-1
sso_registration_scopes = sso:account:access
```

### Steps

```bash
# 1. Log in via SSO
aws sso login --profile preprod-dev

# 2. Configure kubeconfig
AWS_PROFILE=preprod-dev aws eks update-kubeconfig \
  --name preprod-use1-eks \
  --region us-east-1 \
  --role-arn arn:aws:iam::620830101009:role/DeveloperAccess

# 3. Access your namespace
kubectl get pods -n team-<your-team>

# This will be denied (namespace not assigned):
kubectl get pods -n kube-system
```

### Requesting Namespace Access

Namespace access is automatic -- when a team is added to `teams.hcl`, the
`developer_access` EKS access entry is updated to include the team's namespace.
The configuration is in:

```text
infra/live/aws/preprod/us-east-1/platform/eks/terragrunt.hcl
```

If you cannot access your namespace, verify with the platform team that your
team is listed in `teams.hcl` and that you are assigned to the
**DeveloperAccess** permission set in IAM Identity Center for the preprod
account (620830101009).

---

## Private Cluster Access via SSM Tunnel

When the EKS API endpoint is private-only (or you need to bypass public
access restrictions), use the SSM tunnel script.

```bash
# Terminal 1: Start the tunnel
aws sso login --profile platform
AWS_PROFILE=platform ./scripts/eks-tunnel.sh platform-use1-eks us-east-1

# Terminal 2: Use kubectl (kubeconfig is automatically updated by the script)
kubectl get pods -A
```

The script:

1. Discovers the SSM bastion instance by tag
2. Resolves the EKS API endpoint
3. Updates kubeconfig to point to `localhost:8443` with TLS server name override
4. Opens an SSM port-forwarding session

Press Ctrl+C in Terminal 1 to close the tunnel.

---

## Break-Glass Access

In emergencies, use `OrganizationAccountAccessRole` directly:

```bash
aws sso login --profile management

aws eks update-kubeconfig \
  --name platform-use1-eks \
  --region us-east-1 \
  --role-arn arn:aws:iam::829808296602:role/OrganizationAccountAccessRole

kubectl get pods -A
```

This role has full account admin and is exempt from all SCPs. Use only when
purpose-built roles are unavailable.

---

## Troubleshooting

### "error: You must be logged in to the server (Unauthorized)"

**Cause:** The IAM identity used by kubectl is not mapped in EKS access entries,
or the STS token has expired.

**Fix:**

```bash
# Check which identity kubectl is using
aws sts get-caller-identity

# Re-authenticate
aws sso login --profile platform

# Re-run kubeconfig setup with explicit role
AWS_PROFILE=platform aws eks update-kubeconfig \
  --name platform-use1-eks \
  --region us-east-1 \
  --role-arn arn:aws:iam::829808296602:role/PlatformAdmin
```

### "An error occurred (AccessDenied) when calling the AssumeRole operation"

**Cause:** Your SSO session role is not trusted by the target role, or the
trust policy condition does not match your SSO role ARN pattern.

**Fix:**

```bash
# Check your current identity
aws sts get-caller-identity

# Verify the role ARN pattern matches the trust condition
# PlatformAdmin trusts: AWSReservedSSO_AdministratorAccess_*
# DeveloperAccess trusts: AWSReservedSSO_PowerUserAccess_* and AWSReservedSSO_AdministratorAccess_*
```

### Kubeconfig points to wrong server/role

**Cause:** Another tool (eks-tunnel.sh, another update-kubeconfig) overwrote
the kubeconfig entry.

**Fix:**

```bash
# Re-run with the correct role
AWS_PROFILE=platform aws eks update-kubeconfig \
  --name platform-use1-eks \
  --region us-east-1 \
  --role-arn arn:aws:iam::829808296602:role/PlatformAdmin
```

### "connection refused" to localhost:8443

**Cause:** SSM tunnel is not running or has disconnected.

**Fix:** Restart the tunnel in a separate terminal:

```bash
AWS_PROFILE=platform ./scripts/eks-tunnel.sh platform-use1-eks us-east-1
```
