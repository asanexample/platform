# ADR-011: Tailscale Operator for Private Cluster Access

**Date:** 2026-05-23

**Status:** Accepted

## Context

The EKS cluster's API endpoint is private-only (see ADR-010). Developers need a way to run
kubectl, Helm, and Terragrunt commands against the cluster from their laptops without the API
being exposed to the internet.

The initial solution was SSM Session Manager tunneling via `scripts/eks-tunnel.sh`, which forwards
port 8443 through an EC2 bastion to the cluster endpoint. While functional, this approach has
significant friction:

1. **Per-session setup.** Each developer must start the tunnel in a separate terminal before
   running any kubectl command. Forgetting to start it or closing the terminal breaks all
   cluster access.

2. **Single-port forwarding.** The tunnel forwards only the API server port. Accessing other VPC
   resources (databases, internal services, Grafana) requires additional tunnels.

3. **No always-on connectivity.** Engineers frequently context-switch between cluster work and
   other tasks. The tunnel drops when the terminal closes or the SSM session times out (default
   20 minutes idle).

4. **Kubeconfig fragility.** The tunnel script overwrites kubeconfig auth configuration, requiring
   manual fixes to restore the correct AWS profile and role ARN after each session.

### Alternatives Considered

**1. AWS Client VPN.** Managed VPN service that provides full VPC connectivity. Supports
certificate-based and SAML authentication. However, AWS Client VPN costs ~$0.10/hr per connection
plus data transfer, requires managing a VPN endpoint and certificates, and doesn't extend to
Azure or GCP VPCs without additional configuration.

**2. WireGuard on EC2.** Self-hosted WireGuard server in the VPC. Low cost, high performance.
However, requires managing an EC2 instance, WireGuard configuration, key distribution, and
DNS resolution. No built-in user management or SSO integration. Operational burden for a small
team.

**3. Tailscale Kubernetes Operator (chosen).** Runs as a pod on EKS and advertises the VPC CIDR
as a subnet route to the Tailscale mesh network. Developers install the Tailscale client on their
laptops, join the tailnet, and get transparent VPC connectivity. Tailscale handles NAT traversal,
key management, and user authentication. The Operator is managed via CRDs (Connector, ProxyClass),
keeping configuration in version control.

## Decision

Deploy the Tailscale Kubernetes Operator on EKS as a subnet router. The Operator advertises the
VPC CIDR (`10.100.0.0/16`) to the tailnet, giving all tailnet members transparent access to VPC
resources.

### Architecture

```text
Developer laptop (Tailscale client)
  → Tailscale DERP relay / direct WireGuard connection
  → Tailscale Operator pod on EKS (subnet router)
  → VPC private network (10.100.0.0/16)
  → EKS private API endpoint / any VPC resource
```

### Userspace Mode for Cilium Compatibility

The Tailscale subnet router must run in userspace mode (`TS_USERSPACE=true`) because Cilium's eBPF
dataplane manages the kernel routing table. Kernel-mode Tailscale (the default) attempts to create
its own routes and tun interfaces, which conflicts with Cilium's eBPF programs and causes packet
loss or routing loops.

Userspace mode runs the WireGuard tunnel entirely in the Tailscale process, bypassing the kernel
networking stack. This avoids conflicts with Cilium at the cost of slightly higher CPU usage for
tunnel traffic (negligible for developer kubectl traffic).

This is configured via a ProxyClass CRD:

```yaml
apiVersion: tailscale.com/v1alpha1
kind: ProxyClass
metadata:
  name: "${cluster_name}-subnet-router"
spec:
  statefulSet:
    pod:
      tailscaleContainer:
        env:
          - name: TS_USERSPACE
            value: "true"
```

### Split DNS

Split DNS is configured via the Tailscale module's `split_dns` variable. The module creates
`tailscale_dns_split_nameservers` resources that route `*.eks.amazonaws.com` queries to the VPC
DNS resolver (`10.100.0.2`). This is configured with a `depends_on` on the Connector resource so
that DNS entries are only created after the subnet router is online and routes are approved.

### OAuth Credentials

The Operator authenticates to Tailscale's control plane using OAuth client credentials. These are
stored in AWS Secrets Manager (`platform/tailscale/oauth`) and fetched at Terragrunt parse time
via a generated `data "aws_secretsmanager_secret_version"` block. The module itself is
cloud-agnostic — it accepts `oauth_client_id` and `oauth_client_secret` as variables.

### Auto-Approved Routes

The Tailscale ACL policy includes an `autoApprovers` section that automatically approves the VPC
subnet route when advertised by devices tagged `tag:k8s-operator`. This avoids manual route
approval each time the Connector is recreated.

### SSM Tunnel Retained as Fallback

The SSM bastion and `scripts/eks-tunnel.sh` are retained as a fallback for scenarios where
Tailscale is unavailable (new team member not yet on tailnet, Tailscale service outage, incident
where the Operator pod is down).

## Consequences

**Positive:**

- Always-on VPC connectivity — no per-session tunnel setup, no idle timeouts
- Full VPC access, not just the API server — developers can reach Grafana, databases, and other
  internal services through the same connection
- Tailscale handles NAT traversal, key rotation, and WireGuard tunnel management
- User authentication via Tailscale account (can integrate with SSO)
- Configuration is declarative (Connector CRD, ProxyClass CRD) and version-controlled
- Module is cloud-agnostic — same module works for Azure VNets when that's needed
- Kubeconfig uses standard `aws eks update-kubeconfig` with no tunnel-specific workarounds

**Negative:**

- Dependency on Tailscale's hosted control plane for coordination server functionality (key
  exchange, DERP relay, ACL enforcement). Mitigated by the option to migrate to Headscale
  (self-hosted) in the future.
- Tailscale client must be installed on every developer laptop — one more tool to manage
- Userspace mode has slightly higher CPU overhead than kernel mode (negligible for kubectl traffic,
  but relevant if this path is later used for high-throughput data transfer)
- OAuth credentials in Secrets Manager add a secret to manage and rotate
- The Operator pod runs on the EKS cluster itself — if the cluster is completely down, Tailscale
  access is also down (SSM tunnel is the fallback for this case)

**Risks:**

- Tailscale free tier limits to 3 users. Scaling beyond the current team requires upgrading to a
  paid plan. This is a known constraint, not a blocker.
- If the Tailscale Operator pod is evicted or the node it runs on is terminated, VPC access is
  interrupted until the pod is rescheduled. Mitigated by running the Operator on the "system"
  node group with appropriate resource requests.
