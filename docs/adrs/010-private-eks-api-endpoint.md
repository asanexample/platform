# ADR-010: Private-Only EKS API Endpoint

**Date:** 2026-05-23

**Status:** Accepted

## Context

EKS clusters expose a Kubernetes API endpoint that can be configured as public (accessible from
the internet), private (accessible only within the VPC), or both. The platform's EKS cluster runs
in a VPC with private subnets and hosts workloads that will eventually include regulated data
(HIPAA, PCI compliance tiers).

A public API endpoint exposes the cluster's control plane to the internet. While EKS enforces
IAM-based authentication (SigV4), the endpoint is still a target for credential stuffing,
vulnerability scanning, and potential zero-day exploits against the Kubernetes API server.

### Alternatives Considered

**1. Public endpoint with IP allowlisting.** Set `endpoint_public_access = true` with
`public_access_cidrs` restricted to known office/VPN IPs. This allows direct kubectl access from
approved locations without VPC connectivity. However, IP allowlists require maintenance as team
locations change, don't protect against compromised credentials from allowed IPs, and don't meet
the network isolation requirements for HIPAA/PCI compliance tiers.

**2. Public + private endpoints (dual mode).** Enable both endpoints. Traffic from within the VPC
uses the private endpoint; traffic from outside uses the public endpoint. This is the most
convenient for developers but has the same security surface as option 1 for external traffic.

**3. Private-only endpoint (chosen).** Set `endpoint_public_access = false` and
`endpoint_private_access = true`. The API server is only reachable from within the VPC or through
network paths that route into the VPC (VPN, SSM tunnel, subnet router). This eliminates the
internet-facing attack surface entirely.

## Decision

Configure the EKS API endpoint as private-only:

```hcl
endpoint_private_access = true
endpoint_public_access  = false
```

### Per-Cluster Status

Both the **platform** and **preprod** clusters run **private-only** (`endpoint_public_access = false`).
Reach the API over each environment's Tailscale subnet router (operators), or — for ArgoCD on platform
reaching preprod — the TGW + the platform `cross-vpc-dns` PHZ for preprod's endpoint
([ADR-035](035-cross-vpc-dns-resolution.md)). Preprod's earlier public-to-`0.0.0.0/0` posture (a cross-VPC
bootstrap workaround) has since been remediated to private-only, matching platform.

The EKS module now **defaults `endpoint_public_access` to `false`**, so a new unit is private-by-default
(defense-in-depth — a dropped override can't silently expose the API). The only time the public endpoint
is enabled is a full from-scratch bootstrap, which `platctl` toggles on and re-disables automatically
(its unlock/lockdown phases — see `docs/runbooks/platform-rebuild-from-scratch.md`).

### Access Methods

Two access paths provide connectivity to the private endpoint:

1. **Tailscale VPN (primary).** The Tailscale Operator runs on EKS as a subnet router, advertising
   the VPC CIDR (`10.100.0.0/16`) to the tailnet. Split DNS routes `*.eks.amazonaws.com` to the
   VPC DNS resolver (`10.100.0.2`). Developers install the Tailscale client, join the tailnet, and
   kubectl works directly. See ADR-011 for details.

2. **SSM Session Manager tunnel (fallback).** `scripts/eks-tunnel.sh` forwards port 8443 through
   an SSM bastion instance to the cluster endpoint. This requires no VPN but must be started in a
   separate terminal for each session. Used when Tailscale is unavailable or for CI/CD scenarios.

### DNS Resolution

The private endpoint has a DNS name (e.g., `*.eks.amazonaws.com`) that resolves to private IPs
within the VPC. For Tailscale users, split DNS in the Tailscale admin console routes these queries
to the VPC DNS resolver (`10.100.0.2`). For SSM tunnel users, the tunnel script handles DNS
resolution locally.

### Apply / Destroy Workflow

Because the EKS API is private-only, Terragrunt's Helm and Kubernetes providers reach the cluster over
**Tailscale** — the `*-eks-subnet-router` advertises the VPC CIDR and split DNS resolves the private
endpoint to its VPC ENI IPs, so ordinary `apply`/`destroy` of Kubernetes-resident resources (Cilium,
ArgoCD, Backstage, etc.) works directly once you're on the tailnet. **Do NOT enable the public endpoint
for routine operations.**

The single exception is a **full from-scratch teardown/rebuild**, where Tailscale itself (the subnet
router) is among the resources being destroyed — there is then no in-VPC path, so the public endpoint is
a temporary bootstrap escape. `platctl` handles this automatically (its unlock phase re-enables the
endpoint to destroy K8s resources, and its lockdown phase re-disables it), so it should not be toggled by
hand. See `docs/runbooks/platform-rebuild-from-scratch.md`.

## Consequences

**Positive:**

- Zero internet-facing attack surface for the Kubernetes API server
- Meets network isolation requirements for HIPAA and PCI compliance tiers
- All API access is authenticated (IAM SigV4) AND network-restricted (VPC only)
- Aligns with defense-in-depth — even compromised IAM credentials cannot reach the API from
  the public internet

**Negative:**

- Developers must have VPC connectivity (Tailscale or SSM tunnel) before kubectl works — no
  "just configure kubeconfig and go" experience
- CI/CD pipelines need VPC connectivity to deploy to the cluster (currently Terragrunt runs from
  a developer machine with Tailscale; future: self-hosted runners on EKS)
- A full from-scratch teardown (which destroys Tailscale itself) requires temporarily enabling the public
  endpoint as a bootstrap escape, adding operational complexity — but `platctl` automates it (re-disabling
  on lockdown); routine apply/destroy needs no such toggle (it goes over Tailscale)
- Debugging access during incidents requires either working Tailscale or a functioning SSM bastion,
  adding a dependency that may itself be affected by the incident

**Risks:**

- If both Tailscale and SSM bastion are unavailable simultaneously, the cluster is unreachable
  without temporarily enabling the public endpoint via the AWS console or CLI. Mitigated by the
  SSM bastion running on an EC2 instance independent of EKS, so it survives cluster-level failures.
- Forgetting to re-disable the public endpoint after a destroy operation leaves the API exposed.
  Mitigated by documentation and the fact that the Terragrunt live unit configures
  `endpoint_public_access = false`, so the next apply will restore the private-only state.
