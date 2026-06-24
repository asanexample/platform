# ADR-023: EKS Managed Node Groups over Self-Managed or Karpenter

**Date:** 2026-05-23

**Status:** Accepted — **partly superseded by [ADR-078](078-cluster-elasticity-karpenter.md)**: Karpenter now
provisions and consolidates *workload* nodes; managed node groups are retained only for the fixed `system`
(controller/bootstrap) floor.

## Context

EKS worker nodes can be provisioned through three mechanisms:

1. **Managed node groups.** AWS manages the node lifecycle — EC2 instances are created via an
   Auto Scaling Group that AWS controls. Node updates (AMI upgrades, Kubernetes version bumps) are
   performed via a rolling update managed by EKS. The node group resource is an EKS API object.

2. **Self-managed node groups.** The user creates and manages their own Auto Scaling Group, launch
   template, and bootstrap script. Full control over instance lifecycle, AMI selection, and update
   strategy. The ASG is a standalone EC2 resource, not managed by the EKS API.

3. **Karpenter.** A Kubernetes-native autoscaler that provisions nodes on demand based on pending
   pod requirements. Karpenter selects instance types, sizes, and AZs dynamically. It replaces
   both the Cluster Autoscaler and static node group definitions.

The platform uses BYOCNI (Cilium, ADR-008) with a strict deployment ordering (ADR-009). Node
groups must join the cluster after Cilium is installed but must be definable in Terraform with
predictable lifecycle management.

### Alternatives Considered

**1. Self-managed node groups.** Full control over the ASG, launch template, and bootstrap
process. Allows custom AMIs, non-standard bootstrap scripts, and complex update strategies. This
was the original EKS model and is well-understood. However, it requires managing the entire
node lifecycle — AMI patching, draining, cordoning, and replacement — manually or with custom
automation. The operational burden is significant for a small team. Self-managed ASGs also don't
appear in the EKS console's node group view, reducing visibility.

**2. Karpenter.** Eliminates static node group definitions entirely. Pods declare their resource
requirements, and Karpenter provisions right-sized instances on demand. Excellent for variable
workloads with diverse resource profiles. However, Karpenter itself runs as a Kubernetes
controller — it needs nodes to schedule on before it can provision more nodes. This creates a
chicken-and-egg problem with BYOCNI: Karpenter pods need Cilium to network, Cilium needs the
cluster, and Karpenter needs nodes to run. A small static node group is still needed to bootstrap
Karpenter, which reduces the benefit. Additionally, Karpenter uses its own CRDs (NodePool,
EC2NodeClass) and instance selection logic, adding operational complexity that isn't justified at
the platform's current scale.

**3. EKS managed node groups (chosen).** AWS handles the ASG lifecycle, AMI updates, and rolling
replacements. The `aws_eks_node_group` resource is declarative — define the desired instance type,
count, and subnets, and AWS manages the rest. Managed node groups integrate with the EKS API for
version-aware updates and appear in the EKS console. The trade-off is less control over the update
process and AMI selection, but this simplicity is appropriate for the platform's current scale.

## Decision

Use EKS managed node groups for all worker nodes. The `eks-node-group` module
(`infra/modules/aws/eks-node-group/`) creates managed node groups with AWS-managed lifecycle.

### Node Group Configuration

The platform defines two node groups with distinct roles:

| Node Group | Instance Type | Min/Max | Purpose |
|------------|--------------|---------|---------|
| `system` | t3.large | 2–4 | Platform services (Cilium, ArgoCD, cert-manager, monitoring) |
| `workload` | t3.large | 1–6 | Tenant application workloads |

Both groups span all 3 AZs via the kubernetes subnets.

### Node Labels

Each node group has a `node-role` label for scheduling affinity:

```hcl
labels = {
  "node-role" = "system"   # or "workload"
}
```

Platform services can use node selectors or affinity rules to schedule on `system` nodes,
ensuring tenant workloads don't compete with platform infrastructure for resources.

### IAM Configuration

The module creates a node IAM role with four managed policies:

- `AmazonEKSWorkerNodePolicy` — required for node registration
- `AmazonEC2ContainerRegistryReadOnly` — pull images from ECR
- `AmazonSSMManagedInstanceCore` — enable SSM Session Manager on nodes for debugging
- `AmazonEKS_CNI_Policy` — ENI management for Cilium's ENI IPAM mode

### BYOCNI Ordering

The node group unit depends on the Cilium unit via Terragrunt `dependency`. Nodes only join the
cluster after Cilium is installed and ready (ADR-009). Without this ordering, nodes would join
with no CNI and pods would be stuck in `ContainerCreating`.

### Node Hardening (Launch Template)

Each managed node group is backed by a minimal custom **launch template** (no `image_id`, so EKS
still injects the optimized AMI + bootstrap) that:

- **Enforces IMDSv2** (`http_tokens = required`) and sets `http_put_response_hop_limit = 1`, so pods
  cannot reach the instance metadata endpoint and assume the node IAM role's credentials (pods use
  IRSA, ADR-018). This also satisfies the `EnforceIMDSv2` SCP.
- **Encrypts the root EBS volume** (`/dev/xvda`, gp3, `encrypted = true`). EKS's auto-generated
  template encrypts the root volume; a custom template must do the same or the
  `DenyUnencryptedEbsOnLaunch` SCP (ADR-003) blocks node launch ("not authorized to launch instances
  with this launch template"). Adding/altering the launch template forces a rolling node replacement.

## Consequences

**Positive:**

- AWS manages node lifecycle — AMI updates and Kubernetes version bumps are handled via rolling
  replacement with configurable update strategy
- Declarative in Terraform — define instance type, count, and subnets; AWS handles the ASG
- Visible in EKS console — node groups, their health, and update status are visible in the AWS
  console and API
- Simple operational model — no custom bootstrap scripts, no ASG lifecycle hooks, no custom AMIs
- SSM on all nodes — `AmazonSSMManagedInstanceCore` policy allows debugging via Session Manager
  on any worker node, not just the bastion

**Negative:**

- Less control over the update process — AWS decides the rolling update strategy (surge vs.
  unavailable count). Custom drain logic or canary updates require self-managed groups.
- Instance type is fixed per node group — cannot mix instance types within a group (unlike
  Karpenter's dynamic selection). Workloads with diverse resource profiles may need additional
  node groups.
- Managed node groups use the EKS-optimized AMI by default. Custom AMIs require additional
  configuration and may not receive automatic updates.
- t3.large for all groups may be over-provisioned for the `system` group's current workload.
  Right-sizing requires monitoring actual resource usage and adjusting.

**Risks:**

- If AWS's managed rolling update fails (e.g., new nodes can't join due to a CNI issue), nodes
  may be stuck in an updating state. Mitigated by the BYOCNI ordering ensuring Cilium is healthy
  before node group changes are applied.
- t3.large instances have burstable CPU. Sustained CPU-intensive workloads could exhaust CPU
  credits and throttle. Mitigated by monitoring CPU credit balance and switching to m-series
  (non-burstable) instances if needed.
- The platform currently has no cluster autoscaling (Cluster Autoscaler or Karpenter). Node
  counts are static within the min/max range. If workload demand exceeds capacity, pods will
  be pending until manual scaling or Karpenter is added. This is acceptable at current scale.
