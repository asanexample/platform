# EKS Node Groups - US East 1 (Platform)

## Overview

Deploys EKS managed node groups for the platform environment, providing compute capacity for system and application workloads.

## Configuration Details

### Purpose

- Provisions two managed node groups: system (platform components) and workload (application workloads)
- Places all nodes in kubernetes subnets for direct pod networking
- Applies node labels for workload scheduling via nodeSelector or affinity rules

### Dependencies

- **networking**: provides kubernetes subnet IDs for node placement
- **eks**: provides the cluster ID to attach node groups to
- **cilium**: CNI must be deployed first; nodes will not pass readiness checks without a CNI

### Key Configuration Settings

- **system node group**:
  - Instance type: `t3.large`
  - Scaling: 2 min, 2 desired, 4 max
  - Labels: `node-role=system`

- **workload node group**:
  - Instance type: `t3.large`
  - Scaling: 1 min, 2 desired, 6 max
  - Labels: `node-role=workload`

- **Placement**:
  - Both groups: kubernetes subnets

## Usage

```bash
cd infra/live/aws/platform/us-east-1/platform/node-groups
terragrunt plan
terragrunt apply
```

## Dependencies on this Configuration

- **argocd**: requires running nodes to schedule workloads

## Implementation Notes

The Cilium dependency is structural, not just for ordering. In a BYOCNI cluster, nodes that join before the CNI is installed will remain in a NotReady state because no network plugin is available to configure pod networking.
