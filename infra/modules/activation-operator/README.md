# activation-operator

Delivers the **temporary-power activation operator** ([ADR-088](../../../docs/adrs/088-temporary-power-activation.md))
as a hub platform add-on (Terragrunt + Helm, like crossplane/kyverno/cert-manager). The operator
(`operators/activation`, a Kubebuilder controller) mints, holds, and revokes time-boxed borrowed power (the
`Activation` CRD) across the AWS Identity Center plane; it reads the governance-registry
(`WorkforceRole`/`Person`, [ADR-089](../../../docs/adrs/089-governance-registry-topology.md)) for the borrow cap
and eligibility, and fails closed.

This module creates three things:

1. A platform-account **Pod Identity role** (`<cluster_name>-activation-operator`) the operator's ServiceAccount
   assumes. Its *only* permission is to assume the management-account `activation-operator-identity-center` role
   (the cross-account hop to the `sso-admin` plane) — which in turn trusts *only* this role.
2. The **Pod Identity association** binding the ServiceAccount to that role.
3. The **Helm release** — the `Activation` CRD, the manager's RBAC (full `activations`; read-only
   `workforceroles`/`people`; events; leader-election), and the Deployment — in a dedicated `activation-system`
   namespace (restricted PSA, not a tenant namespace).

The operator image is built + cosign-signed by `operator-image.yml`; pin `image` to a digest and re-apply to
upgrade.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | ~> 3.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | ~> 3.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6.0 |
| <a name="provider_helm"></a> [helm](#provider\_helm) | ~> 3.0 |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | ~> 3.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_eks_pod_identity_association.operator](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_pod_identity_association) | resource |
| [aws_iam_role.operator](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.assume_mgmt](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [helm_release.activation_operator](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [kubernetes_config_map_v1.dashboard](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/config_map_v1) | resource |
| [kubernetes_namespace_v1.operator](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace_v1) | resource |
| [aws_iam_policy_document.assume_mgmt](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.trust](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | EKS cluster name. The Pod Identity role is named <cluster\_name>-activation-operator, which the management activation-operator-identity-center role trusts. | `string` | n/a | yes |
| <a name="input_image"></a> [image](#input\_image) | Fully-qualified, digest-pinned operator image (the operator-image.yml build output in platform ECR). | `string` | n/a | yes |
| <a name="input_management_account_id"></a> [management\_account\_id](#input\_management\_account\_id) | Management account ID — home of the activation-operator-identity-center role the operator assumes for the Identity Center plane. | `string` | n/a | yes |
| <a name="input_activator_group"></a> [activator\_group](#input\_activator\_group) | The k8s group the Activate Power backend reaches the cluster as (ADR-088 sole-creator) — bound create-only on Activations. Empty disables the binding. | `string` | `"backstage-activators"` | no |
| <a name="input_create"></a> [create](#input\_create) | Master toggle for the add-on. | `bool` | `true` | no |
| <a name="input_grafana_namespace"></a> [grafana\_namespace](#input\_grafana\_namespace) | Namespace the Grafana sidecar watches for dashboard ConfigMaps (the observability namespace). | `string` | `"observability"` | no |
| <a name="input_helm_timeout"></a> [helm\_timeout](#input\_helm\_timeout) | Helm release timeout (seconds). | `number` | `300` | no |
| <a name="input_helm_wait"></a> [helm\_wait](#input\_helm\_wait) | Wait for the release to become ready (and make it atomic). | `bool` | `true` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | System namespace the operator runs in (NOT a tenant namespace). | `string` | `"activation-system"` | no |
| <a name="input_otel_endpoint"></a> [otel\_endpoint](#input\_otel\_endpoint) | OTLP endpoint for the unified telemetry pipeline (traces+metrics → the cluster otel-collector). Empty disables export. | `string` | `""` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region of the Identity Center instance (passed to the operator as --aws-region). | `string` | `"us-east-1"` | no |
| <a name="input_replicas"></a> [replicas](#input\_replicas) | Operator replica count (leader-elected; >1 gives standby failover). | `number` | `1` | no |
| <a name="input_service_account"></a> [service\_account](#input\_service\_account) | Operator ServiceAccount name (bound to the Pod Identity association). | `string` | `"activation-operator"` | no |
| <a name="input_sync_period"></a> [sync\_period](#input\_sync\_period) | Cache resync period — the safety net re-reconciling every Activation so a dropped expiry self-heals. | `string` | `"2m"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the IAM role + Pod Identity association. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Namespace the operator runs in. |
| <a name="output_pod_identity_role_arn"></a> [pod\_identity\_role\_arn](#output\_pod\_identity\_role\_arn) | ARN of the operator's Pod Identity role (the principal the management Identity Center admin role trusts). |
<!-- END_TF_DOCS -->