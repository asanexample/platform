# Troubleshooting Guide

## Overview

Deep, procedure-level troubleshooting lives in **runbooks** (`docs/runbooks/`) and
**incident docs** (`docs/troubleshooting/`). This page is a quick-reference: common
symptoms, their usual cause on this platform, and where to go next.

## Runbook index

| Area | Runbook |
|------|---------|
| Private cluster access (Tailscale / SSM) | [eks-cluster-access](../../docs/runbooks/eks-cluster-access.md), [tailscale-vpn](../../docs/runbooks/tailscale-vpn.md) |
| SCP denials / org guardrails | [incident-scp-blocking](../../docs/runbooks/incident-scp-blocking.md), [modify-scps](../../docs/runbooks/modify-scps.md), [aws-organizations](../../docs/troubleshooting/aws-organizations.md) |
| Kyverno policy rejections | [kyverno-break-glass](../../docs/runbooks/kyverno-break-glass.md) |
| Supply-chain (cosign / SLSA) rejections | [supply-chain-incidents](../../docs/runbooks/supply-chain-incidents.md), [app-supply-chain-onboarding](../../docs/runbooks/app-supply-chain-onboarding.md) |
| Secrets (ESO / Secrets Manager) | [secrets-management](../../docs/runbooks/secrets-management.md), [secret-rotation](../../docs/runbooks/secret-rotation.md) |
| Environment AWS access (Pod Identity) | [environment-aws-access-pod-identity](../../docs/runbooks/environment-aws-access-pod-identity.md) |
| Observability (Grafana / mimir) | [observability-troubleshooting](../../docs/runbooks/observability-troubleshooting.md), [observability-access](../../docs/runbooks/observability-access.md) |
| Transit Gateway / cross-VPC | [transit-gateway-operations](../../docs/runbooks/transit-gateway-operations.md) |
| Cluster/add-on upgrades | [upgrade-procedures](../../docs/runbooks/upgrade-procedures.md) |

## Common symptoms

### Can't reach the EKS API (`kubectl` times out)

The clusters are **private-only**. Access is via the Tailscale subnet router (an in-cluster
pod) or the SSM bastion.

- **Tailscale split-DNS** sends `*.eks.amazonaws.com` to the VPC resolver via the subnet
  router. If the cluster is scaled to/near **zero nodes**, the router pod is gone and the
  API name won't resolve — use the SSM tunnel or a temporary IP-locked public endpoint.
- After `eks-tunnel.sh`, the kubeconfig server is rewritten to `localhost`; restore
  `AWS_PROFILE` + `--role-arn` if auth breaks. See [eks-cluster-access](../../docs/runbooks/eks-cluster-access.md).
- Don't `export` assumed-role creds in the same shell as `kubectl` — the context's exec
  auth re-assumes from those creds and fails (`not authorized to perform: sts:AssumeRole`).

### Admission webhook errors — `Address is not allowed`

On EKS with the **Cilium overlay**, the managed control plane can only reach webhooks at
**VPC-routable** addresses, but overlay pod IPs aren't. API-server→webhook calls then fail
(`Address is not allowed`), breaking Kyverno / cert-manager / external-secrets. Fix:
those components run on **`hostNetwork`** (`webhook_host_network=true`). See
[Kubernetes Network Design](08-kubernetes-network-design.md#admission-webhooks-on-overlay-eks-gotcha).

### Pods/operations blocked — `no endpoints available for "kyverno-svc"`

A `failurePolicy=Fail` Kyverno webhook with no ready endpoints blocks the resources it
intercepts (e.g. new pods). Usually a transient bootstrap window while Kyverno comes up;
if persistent, check the admission-controller pods. For a legitimate policy override, see
[kyverno-break-glass](../../docs/runbooks/kyverno-break-glass.md). (At zero nodes, Kyverno's
own webhooks are down — node-group config applies are AWS-API-only and unaffected.)

### Node group update fails — `new nodes are not joining` / `VcpuLimitExceeded`

EKS rolling node-group updates **surge** new nodes before terminating old ones. If that
surge exceeds the account's **EC2 On-Demand vCPU service quota** (`L-1216C47A`), launches
fail and the update times out. Work around by **scaling node groups to zero, applying,
then scaling up** (no surge), or raise the quota. New BYOCNI nodes that stay `NotReady`
usually mean Cilium can't start on them (check the `cilium` DaemonSet).

### Pod stuck `Pending`

- `Too many pods` — the node's `--max-pods` cap (EKS/AL2023 defaults it to ENI IP capacity,
  ~35 on `t3.large`). Raise `max_pods` on the node group (overlay decouples pods from ENI IPs).
- `didn't match PersistentVolume's node affinity` — a StatefulSet's EBS volume is AZ-pinned
  and there's no node in that AZ. Ensure per-AZ node coverage (the system group runs
  `desired=3`).
- `didn't have free ports` — a `hostNetwork` pod (e.g. a webhook server) can't bind its
  host port because another pod holds it; give the components distinct ports.

### ExternalSecret not syncing / webhook `CrashLoopBackOff`

ESO's controller syncs from AWS Secrets Manager via IRSA; the webhook only validates. A
webhook `bind: address already in use` on `hostNetwork` means a port clash — its serving
and metrics ports must be moved off conflicting defaults. For sync issues see
[secrets-management](../../docs/runbooks/secrets-management.md).

### An AWS API call is denied by an SCP

Org SCPs deny-list certain actions (regions, root, unencrypted EBS/S3, IAM users, tag
tampering, protected security services). The error is an explicit `AccessDenied` referencing
the SCP. See [incident-scp-blocking](../../docs/runbooks/incident-scp-blocking.md) and the
[SCP control mapping](../../docs/compliance/scp-control-mapping.md).

### Image rejected at admission (cosign / SLSA)

Kyverno `verify-images` / `verify-attestations` (Enforce) reject images that aren't
cosign-signed by the team's own workflow or missing SBOM/SLSA provenance attestations. See
[Authoring Policy-Compliant Workloads](../../CLAUDE.md#authoring-policy-compliant-workloads-kyverno)
and [supply-chain-incidents](../../docs/runbooks/supply-chain-incidents.md).

## First-pass diagnostics

```bash
# Cilium / CNI health
cilium status --verbose
kubectl -n kube-system get pods -l k8s-app=cilium -o wide
# Network drops first, then traces (per the Cilium debugging convention)
hubble observe --type drop

# Why is a pod pending / failing?
kubectl describe pod <pod> -n <ns> | sed -n '/Events:/,$p'

# Admission webhook reachability
kubectl get validatingwebhookconfigurations,mutatingwebhookconfigurations
kubectl -n kyverno get endpoints kyverno-svc

# Node group / AWS-side
aws eks describe-nodegroup --cluster-name <c> --nodegroup-name <ng> --query 'nodegroup.health'
```

## Next Steps

Continue to [Cost Management](19-cost-management.md).
