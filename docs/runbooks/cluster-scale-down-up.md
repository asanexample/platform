# Runbook: Scaling the EKS clusters down to zero (overnight) and back up

We scale the platform + preprod EKS managed node groups to **zero** overnight to save compute cost, then
restore them in the morning. This is safe (PVCs, S3, and all control-plane CRs persist), **but the scale-up
has bitten us repeatedly** — the node churn surfaces several latent issues. This runbook is the procedure +
every failure mode we've hit (incident 2026-06-04) and how to prevent/fix each.

> TL;DR restore order: **scale node groups up → wait for nodes Ready → verify Tailscale DNS/route →
> re-apply `cross-vpc-dns` → clear any stuck `Error` pods (Kyverno must be healthy first).**

## Scale DOWN

The supported path is **`platctl down --env <env>`** — it **drains Karpenter** (deletes the NodePool; its
finalizer waits for the nodes Karpenter manages to terminate) *before* scaling the managed node groups to zero,
so the controller (which runs on the `system` group) doesn't die mid-park and **orphan EC2 instances** (ADR-078).
PVCs, S3, and all control-plane CRs persist. `platctl down` **also stops the SSM bastion** EC2 instance (cost) —
so after a park the SSM tunnel is unavailable until you scale back up (`platctl up` restarts it). See failure
mode #7.

```bash
./bin/platctl down --env platform
./bin/platctl down --env preprod
```

**Break-glass (manual)** — only if platctl is unavailable. Only the `system` group exists now (workload capacity
is Karpenter's); you MUST drain Karpenter and **wait for its NodeClaims/instances to actually terminate** before
zeroing the `system` group, or the EC2 instances are orphaned. `kubectl delete nodepool` returns *before* the
nodes drain, so don't immediately zero the group — `platctl down` does this ordering for you (it also clears
`do-not-disrupt` and deletes the `EC2NodeClass`); prefer it.

```bash
for c in platform preprod; do
  # 1. Clear any do-not-disrupt annotations so Karpenter can reclaim its nodes, then delete the NodePool.
  kubectl --context $c annotate nodes -l karpenter.sh/nodepool karpenter.sh/do-not-disrupt- --all 2>/dev/null || true
  kubectl --context $c delete nodepool --all                    # drain Karpenter FIRST (returns before nodes go)
  # 2. WAIT until Karpenter's NodeClaims are gone (its instances have terminated) — do NOT skip this.
  until [ -z "$(kubectl --context $c get nodeclaims -o name 2>/dev/null)" ]; do
    echo "waiting for $c NodeClaims to terminate…"; sleep 15
  done
  kubectl --context $c delete ec2nodeclass --all                # remove the EC2NodeClass too
  # 3. Only now zero the managed system group.
  AWS_PROFILE=$c aws eks update-nodegroup-config --cluster-name ${c}-use1-eks --nodegroup-name system \
    --scaling-config minSize=0,desiredSize=0 --region us-east-1
done
```

Pods go `Pending`; that's expected. Nothing else to do.

## Scale UP (restore)

**1. Restore capacity.** The supported path is **`platctl up --env <env>`** — it **restarts the SSM bastion**,
re-applies the `node-groups` unit (restoring the `system` group) **and the `karpenter` unit** (force-replacing
the NodePool helm release that `down` deleted, so node autoscaling returns), then runs the reconnect steps
(re-applies `cross-vpc-dns` + restarts the platform ArgoCD controller). Budget ~3–5 min, but it can wait up to
~15 min for nodes/health.

```bash
./bin/platctl up --env platform
./bin/platctl up --env preprod
```

**Break-glass (manual)** — restore the `system` group, then re-apply the `karpenter` unit:

| Cluster | `system` group |
|---|---|
| platform-use1-eks | desired **2** / min 2 / max 3 (t4g.xlarge) |
| preprod-use1-eks | desired **1** / min 1 / max 2 (t4g.large) |

```bash
AWS_PROFILE=platform aws eks update-nodegroup-config --cluster-name platform-use1-eks --nodegroup-name system --scaling-config minSize=2,maxSize=3,desiredSize=2 --region us-east-1
AWS_PROFILE=preprod  aws eks update-nodegroup-config --cluster-name preprod-use1-eks  --nodegroup-name system --scaling-config minSize=1,maxSize=2,desiredSize=1 --region us-east-1
# Recreate the Karpenter NodePool (deleted out-of-band on scale-down) so autoscaling returns. A plain
# `terragrunt apply` reports 0 changes — Terraform still has the NodePool in state, so it doesn't notice the
# kubectl-side deletion. You MUST force-replace the helm release that renders it (this is what `platctl up` does):
(cd infra/live/aws/platform/us-east-1/platform/karpenter && terragrunt apply -replace='helm_release.nodepool[0]')
(cd infra/live/aws/preprod/us-east-1/platform/karpenter && terragrunt apply -replace='helm_release.nodepool[0]')
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
- [ ] **Kyverno admission healthy** on both clusters (failure mode #2) — otherwise environment pods can't be admitted.
- [ ] **No stuck `Error` pods** in environment namespaces (`<team>-<product>-<stage>`, e.g. `alpha-shop-dev`) (failure mode #3).
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

### 2. Kyverno admission-controller CrashLoopBackOff → blocks ALL environment pod admission

**Symptom:** environment pod create/delete fails `Internal error ... no endpoints available for service "kyverno-svc"`.
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

### 7. A whole cluster unreachable over Tailscale: the subnet-router pod wedged in `NeedsLogin`

**Symptom:** after a long downtime (the node group was at zero overnight), `kubectl --context preprod` *resolves*
(so this is NOT the split-DNS conflict #1) but **times out on connect** — the cluster's entire Tailscale route
(e.g. `10.101.0.0/16`) is gone. The `ts-<cluster>-subnet-router-…-0` pod is in **CrashLoopBackOff**.

**Root cause:** the subnet-router pod's stored tailscale node key went **invalid** during the long downtime, so
on restart tailscaled is in `NeedsLogin` and asks the operator to reissue an auth key
(`Requesting a new auth key from operator` → `Waiting … max wait 10m0s`). But the operator reports
`ConnectorReady=True` (it only tracks that it *created* the resources, not that the pod *authenticated*), so it
**never mints a new key** into the secret's `reissue_authkey` field → the pod times out after 10 min →
`tailscaled got signal terminated` → CrashLoop → the route is never advertised → the cluster is unreachable.
The operator's per-cycle `Connector resources synced` log is a red herring — it's "synced" because, to the
operator, nothing is wrong. (The original single-use auth key in `cap-*.hujson` was consumed at first login and is
not re-minted on reissue.)

**Diagnose** (needs PlatformDeployer — PlatformAdmin can't read `tailscale.com` CRs / secrets; reach the cluster
via the SSM tunnel since Tailscale is the very thing that's down). **Caveat:** a manual `platctl down` park
*stops* the SSM bastion, so the tunnel only works once the bastion is running again — `platctl up` restarts it,
or start the bastion instance by hand before relying on the tunnel here:

```bash
kubectl -n tailscale-system get pods                              # subnet-router pod CrashLoopBackOff?
kubectl -n tailscale-system logs <pod> --previous | tail -20      # "NeedsLogin" + "timeout waiting for auth key reissue"
kubectl -n tailscale-system get secret <pod> \
  -o jsonpath='{.data.reissue_authkey}' | wc -c                   # 0 ⇒ operator never wrote a key
```

**Fix:** force a clean re-provision — delete the wedged **state secret** and the **pod**. The operator recreates
the secret with a freshly-minted auth key and the pod re-registers as a new tailnet device; the route auto-approves
via the ACL `autoApprovers` (`tag:k8s` → the VPC CIDR).

```bash
kubectl -n tailscale-system delete secret ts-<cluster>-subnet-router-<hash>-0
kubectl -n tailscale-system delete pod    ts-<cluster>-subnet-router-<hash>-0 --grace-period=0 --force
# pod returns 1/1; `tailscale status` shows the device + its route; then verify kubectl over the REAL
# endpoint with the tunnel KILLED (failure mode #5) — incident 2026-06-04.
```

The old device lingers in the tailnet as a stale offline entry — clean it up in the Tailscale admin (or let it
expire). The router's function doesn't depend on a stable tailnet IP, so the new device is fine.

## Prevention

- **Split-DNS conflict:** PR #208 makes both units agree on `10.100.0.2` for the shared EKS domain. Do not let
  two units write the same tailnet-global split-DNS key with different values.
- **Kyverno `:8080`:** PR #205 disables the conflicting host-port metrics server on hostNetwork.
- Both must be **applied** for the prevention to hold (they're merged to `main`; apply the `policy` and
  `tailscale` units once cluster access is restored).
