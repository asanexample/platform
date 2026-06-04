# Runbook: Scaling the EKS clusters down to zero (overnight) and back up

We scale the platform + preprod EKS managed node groups to **zero** overnight to save compute cost, then
restore them in the morning. This is safe (PVCs, S3, and all control-plane CRs persist), **but the scale-up
has bitten us repeatedly** — the node churn surfaces several latent issues. This runbook is the procedure +
every failure mode we've hit (incident 2026-06-04) and how to prevent/fix each.

> TL;DR restore order: **scale node groups up → wait for nodes Ready → verify Tailscale DNS/route →
> re-apply `cross-vpc-dns` → clear any stuck `Error` pods (Kyverno must be healthy first).**

## Scale DOWN

Set every managed node group to `minSize=0, desiredSize=0` (keep `maxSize`). AWS CLI is fine (it drifts from
the `node-groups` units' `desired_size`; the restore re-aligns). Requires SSO login (`aws sso login --profile
platform` / `--profile preprod`).

```bash
for c in platform preprod; do for ng in system workload; do
  AWS_PROFILE=$c aws eks update-nodegroup-config --cluster-name ${c}-use1-eks --nodegroup-name $ng \
    --scaling-config minSize=0,desiredSize=0 --region us-east-1; done; done
```

Pods go `Pending`; that's expected. Nothing else to do.

## Scale UP (restore)

**1. Restore the node groups** to their normal sizes (AWS CLI, or `terragrunt apply` the four `node-groups`
units which also clears the CLI drift):

| Cluster | `system` | `workload` |
|---|---|---|
| platform-use1-eks | desired **3** (max 4) | desired **1** (max 6) |
| preprod-use1-eks | desired **2** (max 4) | desired **1** (max 6) |

```bash
AWS_PROFILE=platform aws eks update-nodegroup-config --cluster-name platform-use1-eks --nodegroup-name system   --scaling-config minSize=3,maxSize=4,desiredSize=3 --region us-east-1
AWS_PROFILE=platform aws eks update-nodegroup-config --cluster-name platform-use1-eks --nodegroup-name workload --scaling-config minSize=1,maxSize=6,desiredSize=1 --region us-east-1
AWS_PROFILE=preprod  aws eks update-nodegroup-config --cluster-name preprod-use1-eks  --nodegroup-name system   --scaling-config minSize=2,maxSize=4,desiredSize=2 --region us-east-1
AWS_PROFILE=preprod  aws eks update-nodegroup-config --cluster-name preprod-use1-eks  --nodegroup-name workload --scaling-config minSize=1,maxSize=6,desiredSize=1 --region us-east-1
```

**2. Wait for nodes.** Check via the **AWS API first** (kubectl won't work until the in-cluster Tailscale
subnet router is back): `aws eks describe-nodegroup ... --query nodegroup.status` (→ `ACTIVE`) and
`aws ec2 describe-instances ... 'Name=tag:eks:cluster-name,Values=<cluster>'` (→ `running`). The private API is
only reachable via Tailscale (or the SSM tunnel), which needs the subnet-router pod to reschedule first.

**3. Restore-checklist (run through these — each is a failure mode we've hit):**

- [ ] **Tailscale recovered** — `kubectl --context platform get nodes` works. If not, see failure mode #1.
- [ ] **`cross-vpc-dns` re-applied** — preprod's EKS ENI IPs can change on churn; the PHZ goes stale and ArgoCD
      (platform → preprod) fails `dial tcp <old-ENI>:443: i/o timeout`. Re-apply
      `infra/live/aws/platform/us-east-1/platform/cross-vpc-dns`, then hard-refresh the ArgoCD app. ([[project_cross_vpc_dns_dynamic]])
- [ ] **Kyverno admission healthy** on both clusters (failure mode #2) — otherwise tenant pods can't be admitted.
- [ ] **No stuck `Error` pods** in `team-*` (failure mode #3).
- [ ] **Backstage `1/1`** (failure mode #6).

## Known failure modes (and fixes)

### 1. kubectl-over-Tailscale fails: `no such host` — shared split-DNS conflict (THE big one)

**Symptom:** after scale-up, `kubectl --context platform` → `dial tcp: lookup <id>.gr7.us-east-1.eks.amazonaws.com:
no such host`. The **portal still loads** (red herring — its hostname is *public* DNS).

**Root cause:** `tailscale_dns_split_nameservers` is **tailnet-global, keyed by domain**. Both clusters' EKS
endpoints share `us-east-1.eks.amazonaws.com`, and **both** the platform and preprod `tailscale` units set that
key (platform → `10.100.0.2`, preprod → `10.101.0.2`). Last-writer-wins. A scale-up re-apply flips the live
value to preprod's `10.101.0.2`, which is **unreachable** from clients on the platform route and **can't resolve
the platform endpoint** → `no such host`. **The data path is fine** — confirmed by tcpdump (large `[DF]`
segments ACKed) and a `curl https://<api-ENI-IP>` over Tailscale completing a full TLS handshake. **MTU is NOT
the cause** (don't chase it).

**Fix (durable):** point the shared EKS domain at `10.100.0.2` in **both** units — it resolves *both* clusters
(platform directly, preprod via cross-vpc-dns), so the two units agree on one correct value regardless of apply
order (PR #208). **Live unblock:** set `us-east-1.eks.amazonaws.com → 10.100.0.2` in the **Tailscale admin → DNS
→ Nameservers/Split DNS** (terragrunt `-target` can't do it — the unit's `kubernetes_manifest` resources need the
cluster API, which is the very thing that's down). Diagnose with:

```bash
tailscale dns status | grep -A5 'Split DNS'          # what's live
nslookup <platform-eks-host> 10.100.0.2              # platform resolver → resolves both clusters
nslookup <platform-eks-host> 10.101.0.2              # preprod resolver → times out / no answer
```

**Always confirm it's REAL Tailscale, not the SSM bastion** (failure mode #5) before declaring it fixed.

### 2. Kyverno admission-controller CrashLoopBackOff → blocks ALL tenant pod admission

**Symptom:** tenant pod create/delete fails `Internal error ... no endpoints available for service "kyverno-svc"`.
**Cause:** on hostNetwork the controller-runtime metrics server (`--controllerRuntimeMetricsAddress=:8080`) is a
host port; on a rapid restart (informer-sync timeout during API turbulence) the prior `:8080` socket lingers →
`bind: address already in use` → crashloop. The fail-closed webhook then rejects everything.
**Recovery now:** `kubectl delete` the crashlooping admission pod so it reschedules to a node with a free `:8080`.
**Durable fix:** disable `controllerRuntimeMetrics` on hostNetwork (PR #205) — apply the `policy` unit on both clusters.

### 3. Orphaned `Error` pods stuck on dead nodes

Pre-scaledown pods whose node vanished hang in `Error`/Terminating. Force-delete so the ReplicaSet recreates:
`kubectl delete pod -n <ns> <name> --grace-period=0 --force`. **Order matters:** this is blocked until Kyverno
(#2) is healthy (the fail-closed webhook also gates deletes). Fix Kyverno first.

### 4. ArgoCD `ComparisonError` / apps `Unknown` — stale cross-vpc-dns

Preprod EKS ENI IPs change on churn → the cross-VPC PHZ record is stale → ArgoCD (platform → preprod) can't reach
the preprod API. Re-apply `cross-vpc-dns` (re-looks-up the current ENIs), then hard-refresh the app. kubectl is
on a different path so it's unaffected — this only surfaces through ArgoCD.

### 5. The SSM-tunnel false-positive trap

`scripts/eks-tunnel.sh` repoints the **shared** kubeconfig cluster entry to `localhost:8443`, so the
`platform`/`preprod` **alias contexts silently use the bastion**. "kubectl works!" then proves nothing about
Tailscale. To verify Tailscale specifically: `aws eks update-kubeconfig` (restore the real endpoint), **kill the
tunnel** (`pkill -f session-manager-plugin; pkill -f eks-tunnel.sh`), confirm `lsof -i :8443` is empty and the
context server is the real `*.eks.amazonaws.com` endpoint, *then* test.

### 6. Backstage stuck `0/1`

Came up mid-turbulence, readiness probe stuck at 503. `kubectl delete` the pod for a clean restart.

## Prevention

- **Split-DNS conflict:** PR #208 makes both units agree on `10.100.0.2` for the shared EKS domain. Do not let
  two units write the same tailnet-global split-DNS key with different values.
- **Kyverno `:8080`:** PR #205 disables the conflicting host-port metrics server on hostNetwork.
- Both must be **applied** for the prevention to hold (they're merged to `main`; apply the `policy` and
  `tailscale` units once cluster access is restored).
