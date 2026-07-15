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

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | ~> 3.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6.0 |
| <a name="provider_helm"></a> [helm](#provider\_helm) | ~> 3.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudwatch_event_rule.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_rule) | resource |
| [aws_cloudwatch_event_target.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_target) | resource |
| [aws_eks_pod_identity_association.controller](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_pod_identity_association) | resource |
| [aws_iam_role.controller](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.controller](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_sqs_queue.interruption](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue) | resource |
| [aws_sqs_queue_policy.interruption](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue_policy) | resource |
| [helm_release.controller](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.crd](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.nodepool](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.controller_trust](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.queue](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | EKS cluster name (Karpenter settings + IAM/tag scoping + Pod Identity association). | `string` | n/a | yes |
| <a name="input_cluster_security_group_id"></a> [cluster\_security\_group\_id](#input\_cluster\_security\_group\_id) | The EKS cluster security group id — Karpenter nodes attach it (selected by id in the EC2NodeClass). | `string` | n/a | yes |
| <a name="input_node_role_arn"></a> [node\_role\_arn](#input\_node\_role\_arn) | ARN of the EKS node IAM role (created by eks-node-group). Karpenter nodes assume the SAME role; the EC2NodeClass references its name and the controller may PassRole it. | `string` | n/a | yes |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Candidate node subnet ids (the cluster's kubernetes subnets). The EC2NodeClass selects these by id; restricted to one when single\_az. | `list(string)` | n/a | yes |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS region. | `string` | `"us-east-1"` | no |
| <a name="input_capacity_types"></a> [capacity\_types](#input\_capacity\_types) | Allowed capacity types — e.g. ["on-demand"] (platform, stateful-safe) or ["spot","on-demand"] (preprod, cheap/ephemeral). | `list(string)` | <pre>[<br/>  "on-demand"<br/>]</pre> | no |
| <a name="input_consolidate_after"></a> [consolidate\_after](#input\_consolidate\_after) | How long a node must be empty/underutilized before consolidation. | `string` | `"1m"` | no |
| <a name="input_consolidation_policy"></a> [consolidation\_policy](#input\_consolidation\_policy) | Karpenter disruption policy — `WhenEmpty` (only reclaim empty nodes; never disrupts running pods — use on the stateful platform cluster) or `WhenEmptyOrUnderutilized` (bin-pack + reclaim — cheaper, more churn — use on preprod). | `string` | `"WhenEmpty"` | no |
| <a name="input_cpu_limit"></a> [cpu\_limit](#input\_cpu\_limit) | NodePool ceiling on total provisioned vCPU (cost guardrail). | `number` | `32` | no |
| <a name="input_create"></a> [create](#input\_create) | Controls whether resources are created. | `bool` | `true` | no |
| <a name="input_helm_chart_version"></a> [helm\_chart\_version](#input\_helm\_chart\_version) | Karpenter chart version (pinned in \_versions.hcl). | `string` | `"1.13.0"` | no |
| <a name="input_helm_repository"></a> [helm\_repository](#input\_helm\_repository) | Karpenter OCI Helm repository. | `string` | `"oci://public.ecr.aws/karpenter"` | no |
| <a name="input_helm_timeout"></a> [helm\_timeout](#input\_helm\_timeout) | Helm operation timeout (seconds). | `number` | `300` | no |
| <a name="input_helm_wait"></a> [helm\_wait](#input\_helm\_wait) | Wait for the controller release to become ready. | `bool` | `true` | no |
| <a name="input_high_availability"></a> [high\_availability](#input\_high\_availability) | Run 2 controller replicas (prod) vs 1 (dev). | `bool` | `false` | no |
| <a name="input_instance_families"></a> [instance\_families](#input\_instance\_families) | Allowed EC2 instance families. Empty = a sensible default per node\_arch. | `list(string)` | `[]` | no |
| <a name="input_memory_limit"></a> [memory\_limit](#input\_memory\_limit) | NodePool ceiling on total provisioned memory (e.g. "128Gi"). | `string` | `"128Gi"` | no |
| <a name="input_min_instance_cpu"></a> [min\_instance\_cpu](#input\_min\_instance\_cpu) | Exclude instance types with this many vCPUs or fewer. The same fixed per-node DaemonSet slab (~410m CPU: Cilium/Alloy/node-exporter/falco/...) is pure overhead on every node, so tiny 1-2 vCPU nodes waste 20-43% of their CPU on it and can't fit per-node DaemonSets once workloads pack in. A floor forces fewer, bigger nodes that amortize the overhead. 0 = no floor. e.g. 3 requires 4 vCPU+ (lands on c6g.xlarge — cheapest per-vCPU at 8 GiB+). | `number` | `0` | no |
| <a name="input_min_instance_memory_mib"></a> [min\_instance\_memory\_mib](#input\_min\_instance\_memory\_mib) | Exclude instance types smaller than this (MiB). Heavy per-node DaemonSets (Cilium, Beyla, Alloy, node-exporter) consume a fixed slab of every node's memory; too-small nodes exhaust it and the kubelet goes NotReady. 0 = no floor. Set ~6144 to require 8 GiB+ (t4g.large), matching the system node size. | `number` | `0` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace for the Karpenter controller. | `string` | `"karpenter"` | no |
| <a name="input_node_arch"></a> [node\_arch](#input\_node\_arch) | CPU architecture for provisioned nodes (`arm64` Graviton / `amd64`). | `string` | `"arm64"` | no |
| <a name="input_node_termination_grace_period"></a> [node\_termination\_grace\_period](#input\_node\_termination\_grace\_period) | NodePool terminationGracePeriod (ADR-085): the maximum a node drain waits on blocking PodDisruptionBudgets or karpenter.sh/do-not-disrupt pods before Karpenter forcibly drains. Bounds how long a workload PDB can stall consolidation/drift/upgrades. Empty string omits the field (Karpenter default: unbounded). | `string` | `"8h"` | no |
| <a name="input_service_monitor_enabled"></a> [service\_monitor\_enabled](#input\_service\_monitor\_enabled) | Scrape Karpenter's metrics via a ServiceMonitor (the observability stack picks them up). | `bool` | `true` | no |
| <a name="input_single_az"></a> [single\_az](#input\_single\_az) | Pin Karpenter to a single AZ (matches the node groups' single-AZ dev placement) — selects only the first subnet. | `bool` | `false` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | AWS tags. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_controller_role_arn"></a> [controller\_role\_arn](#output\_controller\_role\_arn) | ARN of the Karpenter controller IAM role (Pod Identity). |
| <a name="output_interruption_queue_name"></a> [interruption\_queue\_name](#output\_interruption\_queue\_name) | Name of the SQS interruption queue. |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Namespace the Karpenter controller runs in. |
<!-- END_TF_DOCS -->