# Runbook: Tailscale VPN for Private EKS Access

> **Owner:** Platform team
> **Related:** [EKS Cluster Access](eks-cluster-access.md)
>
> **Last reviewed:** 2026-05-22

---

## Overview

Tailscale provides always-on mesh VPN access to the private EKS cluster,
replacing SSM tunnels as the primary access method. The Tailscale Kubernetes
Operator runs as a subnet router, advertising the VPC CIDR to the tailnet.

```text
Developer laptop (Tailscale client)
  -> Tailscale DERP relay / direct connection
  -> Tailscale Operator pod (subnet router, userspace mode)
  -> VPC private network (10.100.0.0/16)
  -> EKS private API endpoint
```

---

## Table of Contents

1. [Architecture](#architecture)
1. [Full Setup from Scratch](#full-setup-from-scratch)
1. [Rebuilding After Teardown](#rebuilding-after-teardown)
1. [Developer Onboarding](#developer-onboarding)
1. [Tailscale Admin Module](#tailscale-admin-module)
1. [Troubleshooting](#troubleshooting)
1. [Key Details](#key-details)

---

## Architecture

### Components

| Component | Location | Purpose |
|-----------|----------|---------|
| Tailscale account | SaaS (login.tailscale.com) | Control plane, device management |
| ACL policy | `tailscale-admin` unit | Tags, autoApprovers, grants |
| OAuth client | `tailscale-admin` unit | Operator authentication |
| OAuth secret | AWS Secrets Manager | Credential storage |
| Split DNS | `tailscale` unit (K8s) | Route EKS DNS to VPC resolver |
| Tailscale module | `infra/modules/tailscale/` | Helm release + Connector + split DNS |
| Live unit | `infra/live/aws/.../tailscale/` | Environment-specific config |
| ProxyClass | Created by module | Forces userspace networking |
| Connector | Created by module | Advertises VPC CIDR as subnet route |

### Why Userspace Mode

Tailscale's default kernel-mode subnet routing conflicts with Cilium's eBPF
on EKS. The pod's gateway IP falls within the advertised CIDR
(`10.100.0.0/16`), creating a routing loop that breaks outbound connectivity.
The ProxyClass sets `TS_USERSPACE=true` to avoid kernel routing table
modifications.

### Cilium Masquerade

EKS nodes on AL2023 use predictable interface names (`ens5`, not `eth0`).
Cilium's `egressMasqueradeInterfaces` must be set to `ens+` (regex) so the
iptables masquerade rule matches the correct interface. Without this, pods
have no internet egress.

---

## Full Setup from Scratch

Follow these steps to set up Tailscale from zero. Steps 1-2 are manual
(one-time bootstrap). Steps 3-5 document what `tailscale-admin` automates
(shown for reference). Steps 6-8 deploy the infrastructure.

> **If rebuilding**: skip to [Rebuilding After Teardown](#rebuilding-after-teardown).
> Steps 3-5 below are automated by `tailscale-admin` -- skip them and go
> straight to step 6. Step 2 (API key) is also one-time only.

### Step 1: Create Tailscale Account

1. Go to <https://login.tailscale.com> and create an account
1. Free tier covers 3 users, 100 devices

### Step 2: Create API Key for Terraform Provider

In Tailscale admin > **Settings** > **Keys**:

1. Generate a new API key
1. Store it in AWS Secrets Manager:

```bash
aws secretsmanager create-secret \
  --name platform/tailscale/api-key \
  --secret-string '<API_KEY>' \
  --region us-east-1 \
  --profile platform
```

This key authenticates the Tailscale Terraform provider used by both
`tailscale-admin` and `tailscale` units.

### Step 3: Configure ACL Policy

In Tailscale admin console > **Access Controls**, replace the entire policy:

```json
{
  "tagOwners": {
    "tag:k8s-operator": ["autogroup:admin"],
    "tag:k8s":          ["tag:k8s-operator"]
  },
  "grants": [
    {"src": ["*"], "dst": ["*"], "ip": ["*"]}
  ],
  "autoApprovers": {
    "routes": {
      "10.100.0.0/16": ["tag:k8s-operator", "tag:k8s"]
    }
  },
  "ssh": [
    {
      "action": "check",
      "src":    ["autogroup:member"],
      "dst":    ["autogroup:self"],
      "users":  ["autogroup:nonroot", "root"]
    }
  ]
}
```

Key points:

- `tag:k8s-operator` is for the operator pod, `tag:k8s` is for devices it
  manages (subnet router, etc.)
- `autoApprovers` must include **both** `tag:k8s-operator` and `tag:k8s` --
  the operator creates managed devices with `tag:k8s`
- Without `autoApprovers`, subnet routes require manual approval each time
  the Connector is recreated

### Step 4: Create OAuth Client

In Tailscale admin > **Settings** > **OAuth clients**:

1. Click **Generate OAuth client**
1. Check these scopes:
   - **Devices > Core: Write** -- register/manage operator devices
   - **Devices > Routes: Write** -- advertise subnet routes
   - **Keys > Auth Keys: Write** -- create auth keys for managed devices
1. Set tag: `tag:k8s-operator`
1. Save the **client ID** and **client secret**

### Step 5: Store Credentials in Secrets Manager

```bash
aws secretsmanager create-secret \
  --name platform/tailscale/oauth \
  --secret-string '{"clientId":"<CLIENT_ID>","clientSecret":"<CLIENT_SECRET>"}' \
  --region us-east-1 \
  --profile platform
```

If the secret already exists, update it:

```bash
aws secretsmanager put-secret-value \
  --secret-id platform/tailscale/oauth \
  --secret-string '{"clientId":"<CLIENT_ID>","clientSecret":"<CLIENT_SECRET>"}' \
  --region us-east-1 \
  --profile platform
```

### Step 6: Deploy `tailscale-admin`

```bash
cd infra/live/aws/platform/us-east-1/platform/tailscale-admin
terragrunt apply
```

This creates the ACL policy, OAuth client, and Secrets Manager secret.
Split DNS is **not** managed here — it's created by the `tailscale` unit
after the subnet router is online (see next step).

### Step 7: Deploy `tailscale` (K8s operator)

```bash
cd infra/live/aws/platform/us-east-1/platform/tailscale

# First deploy: install operator (creates CRDs) before Connector
terragrunt apply -target=helm_release.tailscale_operator[0]

# Full apply to create ProxyClass, Connector, and split DNS
terragrunt apply
```

Subsequent applies work without `-target` since the CRDs already exist.

Split DNS (`us-east-1.eks.amazonaws.com` -> `10.100.0.2`) is created
automatically after the Connector (subnet router) is online, avoiding the
chicken-and-egg problem where DNS queries route to an unreachable VPC DNS
resolver.

### Step 8: Verify

```bash
# Operator pod running
kubectl get pods -n tailscale-system

# Subnet router connected (look for "Running" state, DERP relay connection)
kubectl logs -n tailscale-system -l app=tailscale -c tailscale --tail=20

# Connector status
kubectl get connector -A

# From your laptop (with Tailscale installed and connected):
ping 10.100.0.34  # any node IP

# kubectl over Tailscale
kubectl get nodes
```

---

## Rebuilding After Teardown

If the cluster was destroyed and rebuilt, follow these steps. The
`tailscale-admin` unit (ACL policy, OAuth client, Secrets Manager secret)
persists across cluster teardowns -- you only need to redeploy the K8s
operator. Split DNS is managed by the `tailscale` unit and is automatically
recreated after the subnet router comes online.

### Pre-flight Checks

1. **EKS public endpoint**: Temporarily enable public access during rebuild
   so Terragrunt can reach the API:

   ```bash
   aws eks update-cluster-config \
     --name platform-use1-eks \
     --region us-east-1 \
     --resources-vpc-config endpointPublicAccess=true \
     --profile platform
   ```

1. **Stale devices**: In Tailscale admin > Machines, remove any offline
   devices from the previous deployment (old subnet routers, operators).
   New deployments get a `-1` suffix if the old name is still registered.

### Deploy

```bash
cd infra/live/aws/platform/us-east-1/platform

# Full stack (handles DAG)
terragrunt run --all apply

# Or just tailscale:
cd tailscale
terragrunt apply -target=helm_release.tailscale_operator[0]
terragrunt apply
```

Split DNS is created automatically by the `tailscale` unit after the
Connector (subnet router) is online -- no manual step needed.

### Post-deploy

1. Verify subnet router is online: `kubectl get pods -n tailscale-system`
1. Verify route is approved in Tailscale admin (should auto-approve via ACL)
1. Disable public endpoint:

   ```bash
   aws eks update-cluster-config \
     --name platform-use1-eks \
     --region us-east-1 \
     --resources-vpc-config endpointPublicAccess=false \
     --profile platform
   ```

1. Test: `kubectl get nodes` (should work over Tailscale, no tunnel)

---

## Developer Onboarding

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

No tunnel, no port forwarding -- just works.

---

## Tailscale Admin Module

The `tailscale-admin` Terragrunt unit manages tailnet-level configuration
via the Tailscale Terraform provider (`tailscale/tailscale` v0.29.1+).
This automates what were previously manual admin console steps:

| What | Provider Resource | Unit |
|------|-------------------|------|
| ACL policy | `tailscale_acl` | `tailscale-admin` |
| OAuth client | `tailscale_oauth_client` | `tailscale-admin` |
| OAuth secret | `aws_secretsmanager_secret` | `tailscale-admin` |
| Split DNS | `tailscale_dns_split_nameservers` | `tailscale` (K8s unit) |

`tailscale-admin` has **no cluster dependencies** -- it manages the tailnet,
not the K8s operator. The OAuth credentials it creates are written to Secrets
Manager at `platform/tailscale/oauth`, which the `tailscale` K8s unit reads.

Split DNS is managed by the `tailscale` K8s unit (not `tailscale-admin`) so
it's created only after the Connector (subnet router) is online. This avoids
a chicken-and-egg problem where split DNS routes queries to VPC DNS before
the subnet router can forward them.

### Authentication

The provider authenticates via an API key stored in Secrets Manager at
`platform/tailscale/api-key`. This is the only remaining manual bootstrap
step (one-time, in Tailscale admin > Settings > Keys).

### Remaining Manual Steps

- Creating the Tailscale account (one-time, step 1)
- Creating the API key for the Terraform provider (one-time, step 2)
- Enabling/disabling EKS public endpoint during rebuild
- Removing stale devices after cluster teardown (admin console or
  `tailscale api delete device`)

---

## Troubleshooting

### Operator CrashLoopBackOff

**Cause:** Pod can't reach `controlplane.tailscale.com:443`. Usually means
pod internet egress is broken.

**Check:**

```bash
# Test pod egress
kubectl run test --rm -it --restart=Never --image=busybox:1.36 \
  -- wget -qO- --timeout=5 http://ifconfig.me

# If that fails, check Cilium masquerade
CILIUM_POD=$(kubectl get pods -n kube-system -l k8s-app=cilium \
  -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n kube-system "$CILIUM_POD" -c cilium-agent \
  -- iptables-save | grep masq
```

**Fix:** The masquerade rule must match `ens+` (not `eth0`). Check
`egressMasqueradeInterfaces` in the Cilium ConfigMap:

```bash
kubectl get cm -n kube-system cilium-config -o yaml | grep egress
```

### Subnet Router Online but Traffic Not Forwarding

**Cause:** Likely kernel-mode routing conflict with Cilium.

**Check:** Verify ProxyClass exists with `TS_USERSPACE=true`:

```bash
kubectl get proxyclass -o yaml
```

The Connector must reference the ProxyClass by name.

### "connection refused" to localhost:8443

**Cause:** Kubeconfig still points to SSM tunnel endpoint.

**Fix:**

```bash
AWS_PROFILE=platform aws eks update-kubeconfig \
  --name platform-use1-eks \
  --region us-east-1 \
  --role-arn arn:aws:iam::829808296602:role/PlatformAdmin
```

### Split DNS Breaking kubectl

**Cause:** Split DNS routes `*.eks.amazonaws.com` to VPC DNS (`10.100.0.2`)
but the subnet router is down, so DNS queries time out.

**Fix:** This should not happen in normal operation -- split DNS is managed
by the `tailscale` unit and depends on the Connector, so it's only created
after the subnet router is online. If it happens anyway, destroy the
`tailscale` unit's split DNS resource:

```bash
cd infra/live/aws/platform/us-east-1/platform/tailscale
terragrunt apply -target='tailscale_dns_split_nameservers.this["us-east-1.eks.amazonaws.com"]' -destroy
```

### Stale Device in Tailscale Admin

After cluster teardown and rebuild, old devices show as offline. The new
deployment creates devices with a `-1` suffix.

**Fix:** Remove old devices in Tailscale admin > Machines > Machine settings
> Remove machine.

---

## Key Details

| Item | Value |
|------|-------|
| Tailnet | `taild3190d.ts.net` |
| OAuth client ID | Managed by `tailscale-admin` (sensitive) |
| Secrets Manager key | `platform/tailscale/oauth` (us-east-1) |
| Subnet route | `10.100.0.0/16` |
| VPC DNS resolver | `10.100.0.2` |
| Split DNS domain | `us-east-1.eks.amazonaws.com` |
| Operator namespace | `tailscale-system` |
| Helm chart version | `1.96.5` |
| Module path | `infra/modules/tailscale/` |
| Live unit path | `infra/live/aws/platform/us-east-1/platform/tailscale/` |
