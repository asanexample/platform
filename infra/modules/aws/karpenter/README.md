# karpenter

**Node autoscaling** ([ADR-078](../../../../docs/adrs/078-cluster-elasticity-karpenter.md) Phase 1). Karpenter
provisions right-sized nodes just-in-time for pending pods and **consolidates** them away when idle —
replacing the static spot workload node group. Cluster-agnostic + parameterized so the same module serves the
**platform** cluster (conservative) and **preprod** (aggressive).

## What it deploys

- **Controller IAM via EKS Pod Identity** (ADR-047, no IRSA) — the standard Karpenter v1 controller policy,
  tag-scoped to this cluster.
- **SQS interruption queue + EventBridge rules** — graceful draining on spot reclaim / maintenance.
- **Helm**: `karpenter-crd` then `karpenter` (controller pinned to the `node-role=system` group so consolidation
  can't evict its own host; ServiceMonitor on).
- **EC2NodeClass + NodePool** via a local chart (so the CRs don't need the CRD at plan time): AL2023, the
  shared node role, subnets/SG by id, `maxPods=110` (BYOCNI), and the **`node.cilium.io/agent-not-ready`
  startup taint** (Cilium removes it once the agent is ready — the BYOCNI ordering hinge, D5).

## Per-cluster shape

| | `capacity_types` | `consolidation_policy` | Use |
|---|---|---|---|
| **platform** | `["on-demand"]` | `WhenEmpty` (never disrupts running stateful pods) | stateful hub — pair with `do-not-disrupt` + PDBs |
| **preprod** | `["spot","on-demand"]` | `WhenEmptyOrUnderutilized` (bin-pack + reclaim) | ephemeral tenant workloads |

`limits.{cpu,memory}` cap total provisioned capacity. Single-AZ (dev) is honored by selecting one subnet.

`node_termination_grace_period` (default `8h`) bounds how long a blocking PodDisruptionBudget or a
`karpenter.sh/do-not-disrupt` pod can stall a node drain before Karpenter forcibly drains — the backstop that
keeps a bad single-replica PDB from wedging consolidation, drift, or an EKS upgrade (ADR-085).

## Inputs of note

`node_role_arn` (the node-groups unit's output — Karpenter nodes assume the same role), plus
`cluster_security_group_id` and `subnet_ids` (the eks/networking units), `node_arch`, and the per-cluster
NodePool knobs above.
