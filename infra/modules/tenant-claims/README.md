# tenant-claims

Delivers tenant **`Tenant` claims** (`XTenant` custom resources) to the federated Crossplane Tenant control
plane ([ADR-046](../../../docs/adrs/046-back-stack-for-developer-self-service.md) /
[ADR-048](../../../docs/adrs/048-federated-per-cluster-crossplane.md)). This is the **current, sole** way a
tenant is provisioned (BACK stack P3, #174) — the old `infra/modules/tenant` module and the
`tenants`/`pod-identity`/`s3-shared` Terragrunt units are retired.

A thin local Helm chart renders **one `XTenant` per entry** in `var.tenants`; the
[`crossplane`](../crossplane/) module's `Tenant` Composition does the actual provisioning. Each map value
**is** the `XTenant` spec, so the unit's HCL is the single, declarative source of truth for each tenant.

Applied as **PlatformDeployer** (a platform principal), so it passes the S1 `restrict-tenant-control-plane`
Kyverno backstop that denies `XTenant` creation by tenant principals.

## What a claim provisions

One `Tenant` claim → the Composition renders the **complete** tenant:

- **Kubernetes** (provider-kubernetes): namespace `team-<team>`, ResourceQuota, LimitRange, default-deny +
  allow NetworkPolicies, CiliumNetworkPolicies, the `team-<team>:developers` RoleBinding, and the per-team
  Kyverno `restrict-images-team-<team>` + `restrict-route-hostnames-team-<team>` policies.
- **AWS, workload account** (provider-aws iam/eks): `Pod-team-<team>` IAM role (deny-escalation boundary) +
  EKS Pod Identity association → the named ServiceAccount; `DeveloperAccess-<team>` IAM role + EKS access
  entry mapping it to the `team-<team>:developers` group.
- **AWS, platform account** (provider-aws ecr, cross-account via `assumeRoleChain`): the
  `team-<team>/<app>` ECR repo + cross-account pull policy, per app.

Not provisioned by the claim: the cosign/SLSA `verify-images`/`verify-attestations` policies (platform-owned
in the [`policy`](../policy/) module) and app delivery (ArgoCD, driven by `teams.hcl`).

## Usage

```hcl
module "tenant_claims" {
  source = "../../modules/tenant-claims"

  tenants = {
    charlie = {
      team      = "charlie"
      hostnames = ["charlie.preprod.aws.refplat.org"]
      apps = {
        api = { repoPath = "k8s/preprod", preview = true }
      }
      aws = {
        serviceAccount = "app-charlie"
        # Generic IAM statements granted to Pod-team-charlie (capped by the deny-escalation boundary).
        # Empty = the role exists but grants nothing. (S3 buckets are NOT created — that was a demo.)
        policyStatements = [
          { sid = "ReadData", effect = "Allow", actions = ["s3:GetObject"], resources = ["arn:aws:s3:::some-bucket/*"] },
        ]
      }
      # resourceQuota omitted → XRD defaults (cpu 4, memory 8Gi, pods 20, …)
      # developerAccess omitted → defaults to enabled
    }
  }
}
```

The live unit (`infra/live/aws/preprod/us-east-1/platform/tenant-claims/`) wires the helm provider (exec auth
as PlatformDeployer) and `depends_on` the `crossplane` unit (the `XTenant` XRD + Composition must exist
first).

## Migrating a team off `teams.hcl`

A team previously provisioned by the Terragrunt path moves over by: (1) adding its `XTenant` here, (2) setting
`migrated = true` on its `teams.hcl` entry (which withdraws it from the now-removed infra loops and tells the
`policy` unit to skip its `restrict-*` policies — the Composition owns those), and (3) keeping its `apps` in
`teams.hcl` for app delivery. See the [tenant onboarding runbook](../../../docs/runbooks/tenant-onboarding.md).

## Inputs

| Name | Description | Type | Default |
| ---- | ----------- | ---- | ------- |
| `create` | Whether to create resources | `bool` | `true` |
| `tenants` | Map of claim name → `XTenant` spec (rendered verbatim) | `any` | `{}` |
| `namespace` | Namespace the Helm release object lives in (claims are cluster-scoped) | `string` | `"crossplane-system"` |
| `helm_wait` | Wait for the Helm apply (XTenant readiness reconciles async) | `bool` | `true` |
| `helm_timeout` | Helm release timeout (seconds) | `number` | `300` |

## Notes

- **Helm `wait` does not gate XTenant readiness.** Helm applies the `XTenant` and returns; Crossplane
  reconciles it asynchronously. Verify with `kubectl get xtenant <name>` (`SYNCED`/`READY`) and
  `kubectl get managed | grep <name>`.
- **Deletion cascades.** Removing a tenant from `var.tenants` deletes its `XTenant`; the Composition tears
  down every managed resource (K8s + both AWS accounts) via finalizers.

## Related

- [`crossplane`](../crossplane/) — the control plane + `Tenant` XRD/Composition (`charts/tenant`)
- [Crossplane Tenant API](../../../docs/architecture/crossplane-tenant-api.md) — XRD schema, Composition pipeline, lifecycle
- ADR-046 (BACK stack), ADR-048 (federated per-cluster Crossplane), ADR-047 (Pod Identity standard)
