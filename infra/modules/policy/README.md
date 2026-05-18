# Policy Module

Deploys [Kyverno](https://kyverno.io/) -- a Kubernetes-native policy engine -- via Helm chart, providing policy-as-code enforcement for cluster compliance guardrails.

> **Note:** This module is a placeholder. Compliance-tier-specific policies will be added in a future iteration.

## Usage

```hcl
module "policy" {
  source = "../policy"

  create          = true
  environment     = "prod"
  compliance_tier = "hipaa"
  chart_version   = "3.3.7"

  additional_policies = {
    require-labels = file("${path.module}/policies/require-labels.yaml")
  }

  tags = {
    Environment = "prod"
    ManagedBy   = "Terragrunt"
  }
}
```

## Compliance Tiers

| Tier | Description |
| ---- | ----------- |
| `standard` | Baseline best practices: require resource labels, disallow privileged containers, enforce resource limits. |
| `hipaa` | Extends standard with audit logging enforcement, encryption-at-rest validation, and access control policies. |
| `pci` | Extends standard with network isolation rules, container image allowlisting, and secret rotation policies. |

Tier-specific policies are not yet implemented -- the `compliance_tier` variable is accepted now so that consuming modules can declare intent and be ready when enforcement is added.

## Resources

| Name | Type |
| ---- | ---- |
| [helm_release.kyverno](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [kubernetes_manifest.additional_policies](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| environment | Environment name (e.g., dev, test, prod) | `string` | n/a | yes |
| additional_policies | Map of policy name to YAML content for custom ClusterPolicy resources | `map(string)` | `{}` | no |
| chart_version | Version of the Kyverno Helm chart | `string` | `"3.3.7"` | no |
| compliance_tier | Compliance tier to enforce (standard, hipaa, pci) | `string` | `"standard"` | no |
| create | Controls whether policy resources should be created | `bool` | `true` | no |
| namespace | Kubernetes namespace to install Kyverno into | `string` | `"kyverno"` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |
| workload | Workload identifier for resource naming | `string` | `"platform"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| compliance_tier | Compliance tier this deployment enforces |
| helm_release_status | Status of the Kyverno Helm release |
| namespace | Kubernetes namespace where Kyverno is installed |
