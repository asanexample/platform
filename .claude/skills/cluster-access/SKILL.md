---
name: cluster-access
description: >-
  How to get kubectl / EKS API access to the private platform and preprod clusters. Use
  when you need to reach a cluster (kubectl get/logs/exec/port-forward), configure or fix
  kubeconfig, or hit "Unauthorized" / "i/o timeout" / "connection refused" against the EKS
  API. The API is private-only by design (ADR-010): reach it over Tailscale, or the SSM
  tunnel as fallback. CRITICAL house norm — never enable the public EKS endpoint for routine
  ops. NOT for in-cluster app RBAC or SSO login issues (see identity runbooks).
---

# Cluster access (private EKS)

The EKS API on both platform and preprod is **private-only by design (ADR-010)** —
`endpoint_public_access = false`. There is no internet-facing API. You reach it from inside
the VPC, over Tailscale. Source of truth: `docs/runbooks/eks-cluster-access.md`,
`docs/runbooks/tailscale-vpn.md`, `docs/adrs/010-private-eks-api-endpoint.md`.

## ⚠️ Never enable the public endpoint for routine ops

This is a hard house norm. `endpoint_public_access` stays `false`. The **only** legitimate
exception is a full from-scratch teardown/rebuild (when Tailscale itself is being destroyed, so
there's no in-VPC path) — and `platctl` automates that toggle (unlock/lockdown), so it's never
done by hand. For anything else, get on the tailnet; don't flip the endpoint.

## Primary path — Tailscale + PlatformAdmin

Each cluster runs a `tailscale` subnet router advertising its VPC CIDR (platform
`10.100.0.0/16`, preprod `10.101.0.0/16`) with split-DNS resolving the private EKS endpoint to
its VPC ENI IPs. Once you're on the tailnet (`tailscale status` lists the subnet routers),
kubectl and terragrunt work directly:

```bash
aws sso login --profile platform

AWS_PROFILE=platform aws eks update-kubeconfig \
  --name platform-use1-eks \
  --region us-east-1 \
  --role-arn arn:aws:iam::<PLATFORM_ACCOUNT_ID>:role/PlatformAdmin

kubectl get nodes
```

`platctl kubeconfig` does this for all configured clusters at once.

## Which role

- **kubectl → `PlatformAdmin`** — cluster-wide **read** on everything, plus a *bounded* operate
  verb set (ADR-040 — read + operate, **not author**). "Operate" is a specific allow-list, not
  general mutation — verify against `infra/modules/cluster-rbac/main.tf` before assuming. It covers:
  `exec`/`port-forward` + ephemeral debug containers; **delete/patch Pods** (only Pods, among
  workloads); evict pods + cordon/drain Nodes; **patch** (not delete) Deployments/StatefulSets/
  DaemonSets for `rollout restart`; and patch/update/delete a **named allow-list of CRDs** (Karpenter
  NodeClaims, Crossplane managed resources). It does **NOT** cover deleting other workload objects —
  e.g. **deleting a Job, Deployment, or anything in a system namespace like `observability` is denied**
  (that needs PlatformDeployer or break-glass, which the model deliberately reserves). You cannot
  create/author resources — author via Git→ArgoCD, AWS infra via Terragrunt (PlatformDeployer),
  emergencies via break-glass (`OrganizationAccountAccessRole`).
- **terragrunt apply / Helm / K8s providers → `PlatformDeployer`** (handled by root.hcl / `_base.hcl`).
- **One-off kubectl writes outside PlatformAdmin's allow-list** (e.g. running a debug pod, clearing a
  stuck finalizer/helm secret) → a separate `platform-deployer` kubectl context, not the default one:
  `AWS_PROFILE=platform aws eks update-kubeconfig --name <cluster> --region us-east-1 --role-arn
  arn:aws:iam::<PLATFORM_ACCOUNT_ID>:role/PlatformDeployer --alias platform-deployer`, then
  `kubectl --context platform-deployer ...`. Forgetting `--context` silently runs against the default
  PlatformAdmin context, which just denies the write. See `docs/runbooks/audit-db-grants.md` for a
  worked example.

## Fallback — SSM tunnel

If Tailscale is unavailable, tunnel via SSM Session Manager (auto-reconnects on idle timeout):

```bash
aws sso login --profile platform
AWS_PROFILE=platform ./scripts/eks-tunnel.sh platform-use1-eks us-east-1   # terminal 1
kubectl get pods -A                                                         # terminal 2
```

**Gotcha:** `eks-tunnel.sh` rewrites your kubeconfig server to `localhost:8443`. When you go
back to Tailscale, re-run `aws eks update-kubeconfig ... --role-arn ...PlatformAdmin` to
restore the real endpoint + role.

## Troubleshooting

- **`Unauthorized`** — IAM identity not in an EKS access entry, or STS token expired. Check
  `aws sts get-caller-identity`, re-`aws sso login`, re-run `update-kubeconfig`.
- **`AccessDenied` on AssumeRole** — the SSO session role isn't trusted by the target role
  (trust-policy condition mismatch).
- **`i/o timeout` to the EKS API** — you're not on the tailnet, or (during a rebuild) the
  tailnet's split-DNS is hijacking resolution before the subnet router is up (`sudo tailscale
  set --accept-dns=false` during bootstrap).
- **`connection refused` to localhost:8443** — the SSM tunnel died; restart `eks-tunnel.sh`.

## References

- `docs/runbooks/eks-cluster-access.md`, `docs/runbooks/tailscale-vpn.md`
- `docs/adrs/010-private-eks-api-endpoint.md`; CLAUDE.md → IAM Roles
- Related skills: **platctl** (`kubeconfig`), **apply-and-destroy** (the rebuild endpoint toggle)
