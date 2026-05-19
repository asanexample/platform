# Cilium CNI - US East 1 (Platform)

## Overview

Deploys Cilium as the CNI for the EKS cluster via Helm, enabling pod networking before any nodes join.

## Configuration Details

### Purpose

- Installs Cilium into the BYOCNI EKS cluster so nodes can reach a Ready state
- Configures AWS-native ENI integration via `cloud_provider = "aws"`
- Sets the Kubernetes API host and port explicitly from the EKS cluster endpoint

### Dependencies

- **eks**: provides cluster endpoint, CA certificate, and cluster ID for Helm provider authentication and Cilium configuration

### Key Configuration Settings

- **Cilium**:
  - cloud_provider: `aws`
  - k8s_service_host: derived from EKS cluster endpoint (https:// prefix stripped)
  - k8s_service_port: `443`
  - Chart version: pinned via shared `helm_versions.cilium`

- **Helm**:
  - helm_wait: `false`
  - Provider auth: exec-based via `aws eks get-token` with OrganizationAccountAccessRole

## Usage

```bash
cd infra/live/aws/platform/us-east-1/platform/cilium
terragrunt plan
terragrunt apply
```

## Dependencies on this Configuration

- **node-groups**: must wait for Cilium to be deployed before nodes can pass readiness checks

## Implementation Notes

`helm_wait` is set to `false` because the CNI must be deployed before node groups exist. There are no nodes to schedule the DaemonSet onto at apply time, so waiting for pod readiness would hang indefinitely. The Helm provider uses exec-based authentication, assuming the OrganizationAccountAccessRole IAM role to obtain a cluster token.
