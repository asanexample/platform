# platform-directory

Provisions the **platform identity-directory database** that backs ADR-084 Phase 1 — the
CloudNative-PG (CNPG) Postgres the triage agent (and later the identity connectors) use as the
person↔external-identity directory. It is a **rebuildable projection of Keycloak**, not a system of
record, so no backups are configured (it rebuilds from source).

## What it provisions

When `create = true` (the default):

- `kubernetes_namespace_v1.this` — a dedicated **platform-infra** namespace (`var.namespace`, default
  `platform-directory`). It is **deliberately not a tenant environment**: it carries no
  `platform.refplat.org/team` label, so the tenant Kyverno policies (ECR-only images, mandatory
  probes/limits) do not apply — exactly how `keycloak` and `backstage` run their CNPG databases. PSA
  labels are set to `baseline` enforce / `restricted` warn+audit.
- `kubernetes_manifest.db` — a `postgresql.cnpg.io/v1` **Cluster** (`var.db_cluster_name`, default
  `triage-copilot-db`) with `var.instances` (default 1 — a rebuildable projection needs no HA) and
  `var.storage_size` (default `5Gi`). It bootstraps a `directory` database owned by a `directory`
  role, disables superuser access, and sets `karpenter.sh/do-not-disrupt` so Karpenter won't
  voluntarily disrupt the Postgres node.
- `random_password.db` + `kubernetes_secret_v1.db_role` — a deterministic password for the `directory`
  **managed role**. CNPG sets the role's password from this Secret, so the connection string is
  deterministic and the module never has to read CNPG's async-generated `-app` secret (which would
  race at apply time). The password is alphanumeric-only, safe across the Secrets-Manager → ESO → DSN
  path.
- `kubernetes_manifest.db_ingress` — a default-deny **CiliumNetworkPolicy** (`allow-consumer-to-db`)
  that allows **only** the consumer namespace to reach the DB on TCP 5432 (see below).
- `aws_secretsmanager_secret.db` (+ version) — publishes the Postgres connection string to Secrets
  Manager at `var.db_secret_name` (default `platform/triage-copilot/directory-db`) as
  `{"uri":"postgresql://directory:…@<cluster>-rw.<ns>.svc.cluster.local:5432/directory"}`.
- `null_resource.cnpg_finalizer_cleanup` — destroy-time CNPG finalizer cleanup (see below).

The module declares **no provider block** — the live unit injects the `kubernetes` provider (EKS
exec-auth as the deployer role) and the `aws` provider from `root.hcl`.

## Consumer-namespace secret handoff

The directory DB lives in its **own** namespace; its consumer (the triage agent) lives in another. The
two are bridged out-of-band so the consumer never shares the directory's namespace or posture
(ADR-084 D13 — the directory stays out of the agent sandbox):

- `consumer_namespace` (default `platform-agent-triage-copilot`) is the **only** namespace the
  `allow-consumer-to-db` CiliumNetworkPolicy lets reach Postgres on 5432.
- The connection string is handed off via **Secrets Manager** (`db_secret_name`), not a shared
  in-cluster Secret: the consumer's own ExternalSecret reads that key (as `DATABASE_URL`/`uri`) and
  connects cross-namespace. Keeping the consumer in its own namespace leaves **every** tenant Kyverno
  policy intact for the agent — no posture change.

## Destroy-time CNPG finalizer cleanup

CNPG/PVC-protection finalizers can hang a namespace delete during teardown (the same problem the
`keycloak` module solves). `null_resource.cnpg_finalizer_cleanup` force-deletes the CNPG `Cluster` →
pods → PVCs **before** the namespace is removed, so the namespace finalizes cleanly:

- `finalizer_clear_script` — path to `scripts/k8s-finalizer-clear.sh`. **Empty (the default) disables
  the cleanup**; the live unit wires it in to enable it. It runs only as a `when = destroy`
  provisioner.
- `deployer_role_arn`, `cluster_name`, `region` — the EKS access context the script assumes/targets
  to delete `cluster.postgresql.cnpg.io`, `pod`, and `persistentvolumeclaim` refs in `var.namespace`.

These are stored on the resource's `triggers` so they remain available at destroy time even after the
inputs are gone.

## Key outputs

- `namespace` — the directory DB namespace.
- `db_secret_name` — the Secrets Manager name holding the directory Postgres connection string
  (`uri`), for the consumer's ExternalSecret to read.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.11 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | ~> 3.0 |
| <a name="requirement_null"></a> [null](#requirement\_null) | >= 3.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | >= 3.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6.0 |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | ~> 3.0 |
| <a name="provider_null"></a> [null](#provider\_null) | >= 3.0 |
| <a name="provider_random"></a> [random](#provider\_random) | >= 3.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_secretsmanager_secret.db](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret_version.db](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [kubernetes_manifest.db](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_manifest.db_ingress](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_namespace_v1.this](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace_v1) | resource |
| [kubernetes_secret_v1.db_role](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/secret_v1) | resource |
| [null_resource.cnpg_finalizer_cleanup](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [random_password.db](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | EKS cluster name (for the teardown finalizer-cleanup). | `string` | `""` | no |
| <a name="input_consumer_namespace"></a> [consumer\_namespace](#input\_consumer\_namespace) | The namespace allowed to reach the DB on 5432 (the triage agent's). | `string` | `"platform-agent-triage-copilot"` | no |
| <a name="input_create"></a> [create](#input\_create) | Whether to provision the directory database. | `bool` | `true` | no |
| <a name="input_db_cluster_name"></a> [db\_cluster\_name](#input\_db\_cluster\_name) | CloudNativePG Cluster name. | `string` | `"triage-copilot-db"` | no |
| <a name="input_db_secret_name"></a> [db\_secret\_name](#input\_db\_secret\_name) | Secrets Manager name for the published connection string (uri). | `string` | `"platform/triage-copilot/directory-db"` | no |
| <a name="input_deployer_role_arn"></a> [deployer\_role\_arn](#input\_deployer\_role\_arn) | Deployer role ARN (for the teardown finalizer-cleanup). | `string` | `""` | no |
| <a name="input_extra_consumer_namespaces"></a> [extra\_consumer\_namespaces](#input\_extra\_consumer\_namespaces) | Additional namespaces allowed to reach the DB on 5432 — e.g. the activation operator's, which writes the governance audit (ADR-088 §3.6). | `list(string)` | `[]` | no |
| <a name="input_finalizer_clear_script"></a> [finalizer\_clear\_script](#input\_finalizer\_clear\_script) | Path to scripts/k8s-finalizer-clear.sh (empty disables the teardown cleanup). | `string` | `""` | no |
| <a name="input_instances"></a> [instances](#input\_instances) | CNPG instance count (1 = single; a rebuildable projection needs no HA). | `number` | `1` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Platform-infra namespace for the directory DB (NOT a tenant env — no platform.refplat.org/team label, so the tenant Kyverno policies don't apply). | `string` | `"platform-directory"` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region (for the teardown finalizer-cleanup). | `string` | `"us-east-1"` | no |
| <a name="input_secret_recovery_window_days"></a> [secret\_recovery\_window\_days](#input\_secret\_recovery\_window\_days) | Secrets Manager recovery window. 0 = force-delete (setup-friendly); raise for prod. | `number` | `0` | no |
| <a name="input_storage_size"></a> [storage\_size](#input\_storage\_size) | CNPG volume size. | `string` | `"5Gi"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the generated Secrets Manager secret. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_db_secret_name"></a> [db\_secret\_name](#output\_db\_secret\_name) | Secrets Manager name holding the directory Postgres connection string (uri). |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | The directory DB namespace. |
<!-- END_TF_DOCS -->
