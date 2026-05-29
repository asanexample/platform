# tenants

Provisions tenant namespaces, network policies, and isolation resources for application teams in the preprod cluster. Team definitions are sourced from `../teams.hcl`.

## Module

`infra/modules/tenant`

## Dependencies

- `eks` — `../eks`
- `node_groups` — `../node-groups`
- `gateway_config` — `../gateway-config`

## Teams (from `teams.hcl`)

| Team    | Mode      | Apps                                                  | Preview |
|---------|-----------|-------------------------------------------------------|---------|
| `alpha` | namespace | `demo` (github.com/gangster/app-alpha, `k8s/preprod`) | yes     |
| `bravo` | namespace | `demo` (github.com/gangster/app-bravo, `k8s/preprod`) | no      |

## Key Inputs

| Input                          | Value                    | Notes                                                                   |
|--------------------------------|--------------------------|-------------------------------------------------------------------------|
| `tenants`                      | Derived from `teams.hcl` | Each team gets `{ mode = "namespace" }`                                 |
| `gateway_namespace`            | `"default"`              | Namespace containing the Gateway resource                               |
| `vcluster_storage_class`       | `"gp2"`                  | Storage class for vCluster PVCs (unused — all teams are namespace mode) |
| `vcluster_persistence_enabled` | `false`                  |                                                                         |

## Commands

```bash
# Plan
AWS_PROFILE=management terragrunt plan

# Apply
AWS_PROFILE=management terragrunt apply
```
