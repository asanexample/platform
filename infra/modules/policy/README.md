# Policy

Deploys Kyverno, a Kubernetes-native policy engine, via Helm and supports applying custom ClusterPolicy resources. Includes a `compliance_tier` variable for future compliance-tier-specific policy sets (standard, HIPAA, PCI) -- currently a placeholder with no tier-specific logic implemented. Custom policies can be provided as YAML strings via the `additional_policies` map.

## Usage

```hcl
module "policy" {
  source = "../../modules/policy"

  environment     = "preprod"
  compliance_tier = "standard"

  additional_policies = {
    require-labels = <<-YAML
      apiVersion: kyverno.io/v1
      kind: ClusterPolicy
      metadata:
        name: require-labels
      spec:
        validationFailureAction: Enforce
        rules:
          - name: check-team-label
            match:
              any:
                - resources:
                    kinds:
                      - Pod
            validate:
              message: "The label 'team' is required."
              pattern:
                metadata:
                  labels:
                    team: "?*"
    YAML
  }

  tags = {
    Environment = "preprod"
    ManagedBy   = "terraform"
  }
}
```

## Examples

### Disabled Module

```hcl
module "policy" {
  source = "../../modules/policy"

  create      = false
  environment = "preprod"
}
```

### Minimal

```hcl
module "policy" {
  source = "../../modules/policy"

  environment = "platform"
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | >= 2.5.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | >= 2.10.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_helm"></a> [helm](#provider\_helm) | >= 2.5.0 |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | >= 2.10.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [helm_release.kyverno](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [kubernetes_manifest.additional_policies](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name (e.g., dev, test, prod) | `string` | n/a | yes |
| <a name="input_additional_policies"></a> [additional\_policies](#input\_additional\_policies) | Map of policy name to YAML content for custom ClusterPolicy resources | `map(string)` | `{}` | no |
| <a name="input_chart_version"></a> [chart\_version](#input\_chart\_version) | Version of the Kyverno Helm chart | `string` | `"3.3.7"` | no |
| <a name="input_compliance_tier"></a> [compliance\_tier](#input\_compliance\_tier) | Compliance tier to enforce (standard, hipaa, pci) | `string` | `"standard"` | no |
| <a name="input_create"></a> [create](#input\_create) | Controls whether policy resources should be created | `bool` | `true` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Kubernetes namespace to install Kyverno into | `string` | `"kyverno"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all resources | `map(string)` | `{}` | no |
| <a name="input_workload"></a> [workload](#input\_workload) | Workload identifier for resource naming | `string` | `"platform"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_compliance_tier"></a> [compliance\_tier](#output\_compliance\_tier) | Compliance tier this deployment enforces |
| <a name="output_helm_release_status"></a> [helm\_release\_status](#output\_helm\_release\_status) | Status of the Kyverno Helm release |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Kubernetes namespace where Kyverno is installed |
<!-- END_TF_DOCS -->

## Notes

- Compliance tiers (`standard`, `hipaa`, `pci`) are validated but not yet implemented -- the variable exists for future use.
- Custom policies in `additional_policies` must be valid YAML that deserializes to a Kubernetes manifest. Each value is passed through `yamldecode()`.
- Kyverno is installed with `atomic = true`, so a failed install is automatically rolled back.
