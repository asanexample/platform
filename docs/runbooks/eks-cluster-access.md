# Runbook: EKS Cluster Access

> **Roles:** PlatformAdmin, PlatformDeployer, DeveloperAccess-\<team\>
> **Related ADR:** [007-iam-role-model](../adrs/007-iam-role-model.md), [039-per-team-developer-rbac](../adrs/039-per-team-developer-rbac.md), [040-platform-engineer-access-model](../adrs/040-platform-engineer-access-model.md)
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
  --role-arn arn:aws:iam::<PLATFORM_ACCOUNT_ID>:role/PlatformAdmin
```

1. Verify: `kubectl get nodes`

### Fallback

If Tailscale is unavailable, use the [SSM tunnel](#private-cluster-access-via-ssm-tunnel).

---

## Platform Engineer: kubectl Setup

Platform engineers use the **PlatformAdmin** role for cluster access. It is **read + operate, not
author** (ADR-040): you can inspect everything, view logs, `exec`/`port-forward`, delete a stuck pod,
cordon/drain nodes, and `kubectl rollout restart` — but you **cannot** create or edit resources. To
author resources, commit to Git (ArgoCD syncs); for AWS infra use Terragrunt (PlatformDeployer); for
genuine emergencies that must bypass the pipelines, use break-glass (`OrganizationAccountAccessRole`).

### Prerequisites

- AWS CLI v2 with SSO configured
- kubectl installed
- An SSO profile for the platform account (see AWS config below)

### AWS Config

Add to `~/.aws/config`:

```ini
[profile platform]
sso_session = centric
sso_account_id = <PLATFORM_ACCOUNT_ID>
sso_role_name = AdministratorAccess

[sso-session centric]
sso_start_url = https://d-XXXXXXXXXX.awsapps.com/start
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
  --role-arn arn:aws:iam::<PLATFORM_ACCOUNT_ID>:role/PlatformAdmin

# 3. Verify access
kubectl get pods -A
```

The `--role-arn` flag embeds the PlatformAdmin role in the kubeconfig, so
subsequent `kubectl` commands automatically assume it.

---

## Developer: Namespace-Scoped kubectl

Each developer uses their team's own **DeveloperAccess-\<team\>** role on the
**preprod** cluster, which grants edit access to that team's namespace only. A
developer can assume only their own team's role (the role's trust is restricted to
the team's `Dev-<team>` SSO permission set). The platform cluster does not have
developer access -- it is admin-only. See ADR-039 for the full model.

> ⚠️ **Not yet provisioned (#364 / ADR-068).** The `DeveloperAccess-<team>` IAM role
> and its EKS access entry are **not emitted** by the Crossplane Composition today (it
> creates only the in-cluster `RoleBinding`), so the `aws eks update-kubeconfig
> --role-arn …/DeveloperAccess-<team>` flow below **does not work yet** — there is no
> role to assume into. **Until OIDC-native developer cluster auth (#364, ADR-068) lands,
> use `./bin/platctl kubeconfig` / a PlatformAdmin context.** The steps below document
> the intended end-state. (#647 was closed but the capability was superseded by #364, not
> delivered.)

### Prerequisites

- AWS CLI v2 with SSO configured
- kubectl installed
- Membership in your team's `Developers-<team>` Identity Center group (managed by
  the platform team)

### AWS Config

Add to `~/.aws/config` (use your team's `Dev-<team>` permission set):

```ini
[profile preprod-dev]
sso_session = centric
sso_account_id = <PREPROD_ACCOUNT_ID>
sso_role_name = Dev-<your-team>     # e.g. Dev-alpha

[sso-session centric]
sso_start_url = https://d-XXXXXXXXXX.awsapps.com/start
sso_region = us-east-1
sso_registration_scopes = sso:account:access
```

### Steps

```bash
# 1. Log in via SSO
aws sso login --profile preprod-dev

# 2. Configure kubeconfig (assume your team's DeveloperAccess-<team> role)
AWS_PROFILE=preprod-dev aws eks update-kubeconfig \
  --name preprod-use1-eks \
  --region us-east-1 \
  --role-arn arn:aws:iam::<PREPROD_ACCOUNT_ID>:role/DeveloperAccess-<your-team>

# 3. Access your environment namespace (<team>-<product>-<stage>, e.g. alpha-shop-dev)
kubectl get pods -n alpha-shop-dev

# These will be denied (other namespace / cluster-scoped):
kubectl get pods -n bravo-shop-dev
kubectl get pods -n kube-system
```

### Requesting Namespace Access

Access is provisioned when a team's environment is onboarded — the namespace
`RoleBinding` (→ ClusterRole `environment-developer`), and (when emitted) the per-team
`DeveloperAccess-<team>` role + its group-mapped EKS access entry, come from the
**Crossplane Environment Composition** driven by the `gitops/` registries
(`gitops/teams/`, `gitops/products/`, `gitops/environments/`) — `teams.hcl` is retired.
The SSO permission set/group are added in the `identity-center` unit. See the
[Environment Onboarding](environment-onboarding.md) runbook.

> **Note (#364 / ADR-068):** the per-team `DeveloperAccess-<team>` IAM role and its EKS
> access entry are **not yet emitted** by the Composition (see the caveat at the top of
> this section). Until OIDC-native developer cluster auth (#364) lands, the namespace
> `RoleBinding` exists but there is no team-scoped IAM role to assume into it — use
> `./bin/platctl kubeconfig` / PlatformAdmin.

If you cannot access your namespace, verify with the platform team that your team's
registry entries (`gitops/teams/<team>.yaml` + an `XEnvironment` claim under
`gitops/environments/`) exist and that you are a member of the `Developers-<team>`
Identity Center group for the preprod account (<PREPROD_ACCOUNT_ID>).

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
  --role-arn arn:aws:iam::<PLATFORM_ACCOUNT_ID>:role/OrganizationAccountAccessRole

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
  --role-arn arn:aws:iam::<PLATFORM_ACCOUNT_ID>:role/PlatformAdmin
```

### "An error occurred (AccessDenied) when calling the AssumeRole operation"

**Cause:** Your SSO session role is not trusted by the target role, or the
trust policy condition does not match your SSO role ARN pattern.

**Fix:**

```bash
# Check your current identity
aws sts get-caller-identity

# Verify the role ARN pattern matches the trust condition
# PlatformAdmin trusts:          AWSReservedSSO_AdministratorAccess_*
# DeveloperAccess-<team> trusts: AWSReservedSSO_Dev-<team>_* (that team's set only)
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
  --role-arn arn:aws:iam::<PLATFORM_ACCOUNT_ID>:role/PlatformAdmin
```

### "connection refused" to localhost:8443

**Cause:** SSM tunnel is not running or has disconnected.

**Fix:** Restart the tunnel in a separate terminal:

```bash
AWS_PROFILE=platform ./scripts/eks-tunnel.sh platform-use1-eks us-east-1
```
