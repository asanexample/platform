# Crossplane Tenant API

How tenants are provisioned on this platform. A team is a single declarative **`Tenant` claim**
(`XTenant`); a Crossplane **Composition** reconciles it into the complete tenant footprint — Kubernetes,
AWS (workload account), and cross-account ECR. This is the **current, sole** provisioning path (BACK stack
P3, [#174]). The previous Terragrunt path (`infra/modules/tenant` + the `tenants`/`pod-identity`/`s3-shared`
units) is **retired**.

See also: [ADR-046](../adrs/046-back-stack-for-developer-self-service.md) (adopt the BACK stack),
[ADR-048](../adrs/048-federated-per-cluster-crossplane.md) (federated topology),
[ADR-047](../adrs/047-pod-identity-standard.md) (Pod Identity standard).

## Federated topology

Crossplane is **federated — one instance per cluster**, not a central hub reaching into every account. Each
workload cluster runs its own Crossplane and provisions its **own** tenants locally, using its own EKS Pod
Identity to authenticate the providers. The single cross-account hop is **ECR**: tenant image repos live in
the platform account, so the provider-aws `ecr` provider assumes the platform `crossplane-ecr-provisioner`
role (`assumeRoleChain`) for those resources only.

```text
            platform account                         preprod cluster (its own Crossplane)
  ┌───────────────────────────────┐      ┌────────────────────────────────────────────────┐
  │  crossplane-ecr-provisioner    │◀─────│ provider-aws-ecr  (assumeRoleChain, ECR only)   │
  │  ECR repos: team-*/*           │      │ provider-aws-iam/eks (Pod Identity, local)      │
  └───────────────────────────────┘      │ provider-kubernetes  (in-cluster)               │
                                          │ Tenant XRD + Composition + functions            │
                                          └────────────────────────────────────────────────┘
```

The control plane (Crossplane core, providers, XRD/Composition) is installed by the
[`crossplane`](../../infra/modules/crossplane/) Terragrunt module as a normal add-on unit. Claims are
delivered separately (below).

## The `Tenant` claim (`XTenant`)

`apiVersion: platform.refplat.org/v1alpha1`, `kind: XTenant`, **cluster-scoped** (Crossplane v2 XR). The
spec is the tenant-facing contract — no infra constants leak into it:

| Field | Required | Purpose |
| ----- | -------- | ------- |
| `team` | yes | Team key; drives the `team-<team>` namespace and every per-team resource name |
| `hostnames` | — | Gateway-API hostnames the team may claim (feeds `restrict-route-hostnames`, ADR-029) |
| `gatewayNamespace` | — (default `default`) | Namespace of the shared Gateway (ingress source) |
| `resourceQuota` | — (defaults match the old tenant module) | `cpu`/`memory`/`pods`/`services`/`loadbalancers`/`pvcs`/`storage` |
| `complianceTier` | — (default `standard`) | `standard`/`hipaa`/`pci` |
| `apps` | — | Map `<app> → { repoPath, preview }`; each app gets an ECR repo `team-<team>/<app>` |
| `aws` | — | `serviceAccount` (the named SA the Pod Identity association binds) + `policyStatements[]` (generic IAM granted to `Pod-team-<team>`, capped by the deny-escalation boundary) |
| `developerAccess` | — (default `enabled: true`) | Provision `DeveloperAccess-<team>` + the EKS access entry |

A minimal example lives in `infra/modules/crossplane/examples/tenant-gamma.yaml`; the live claims are YAML
files in `gitops/tenant-claims/<env>/` (one `XTenant` per file).

## What the Composition provisions

The Composition (`infra/modules/crossplane/charts/tenant/files/composition.yaml`, mode `Pipeline`) renders,
from one claim:

**Kubernetes** (via `provider-kubernetes` `Object`s):

- Namespace `team-<team>` (labeled `platform.refplat.org/tenant`), ResourceQuota, LimitRange
- default-deny + allow-DNS/allow-gateway NetworkPolicies, CiliumNetworkPolicies (gateway/Envoy + Pod-Identity egress)
- `team-<team>:developers` RoleBinding (binds the `tenant-developers` ClusterRole — ADR-039)
- per-team Kyverno `restrict-images-team-<team>` + `restrict-route-hostnames-team-<team>` ClusterPolicies

**AWS — workload account** (via `provider-aws` `iam`/`eks`, ProviderConfig `default` = Pod Identity):

- `Pod-team-<team>` IAM role (trust `pods.eks.amazonaws.com` + `aws:SourceAccount`; **deny-escalation
  permissions boundary**; `Team` tag) + its RolePolicy (the claim's `aws.policyStatements`)
- EKS Pod Identity association `(cluster, team-<team>, aws.serviceAccount) → Pod-team-<team>`
- `DeveloperAccess-<team>` IAM role (trust = the team's `Dev-<team>` SSO permission set in mgmt + workload
  accounts) + EKS **access entry** mapping it to the `team-<team>:developers` group

**AWS — platform account** (via `provider-aws` `ecr`, ProviderConfig `platform-ecr` = assumeRoleChain):

- `team-<team>/<app>` ECR repo per app (`IMMUTABLE_WITH_EXCLUSION` for cosign `sha256-*` tags, scan-on-push)
  plus a cross-account RepositoryPolicy (pull for the preprod and prod account roots)

**Not** provisioned by the claim — these stay platform-owned in the [`policy`](../../infra/modules/policy/)
module for **all** teams (a tenant must not declare its own signature trust root): the cosign/SLSA
`verify-images-team-<team>` + `verify-attestations-team-<team>` policies. The `policy` unit skips only the
per-team `restrict-*` guardrails for migrated teams (`migrated_teams` input), since the Composition owns
those. This **supply-chain split** — guardrails in the claim, trust roots in the platform — is deliberate
(ADR-014/046).

## Composition pipeline

```text
load-environment   function-environment-configs   merges the tenant-cluster-config EnvironmentConfig
       │                                           into the pipeline context (cluster constants)
render-resources   function-go-templating          renders all of the above from spec + context
       │
ready              function-auto-ready              marks the XR Ready when its resources are Ready
```

**Cluster constants** (ECR registry, workload + management account IDs, cluster name, the permissions-boundary
ARN, the cross-account pull accounts, the ECR ProviderConfig name) are **not** in the claim — they're injected
via a Helm-templated **`EnvironmentConfig`** (`tenant-cluster-config`) read by the go-template as
`index .context "apiextensions.crossplane.io/environment"`. This keeps the claim API clean and per-cluster
config out of the tenant-facing spec. The Composition itself ships **raw** (`.Files.Get`) so Helm doesn't try
to process its inline go-template `{{ }}`.

## Claim delivery & lifecycle

Claims are **GitOps-delivered**: each is a YAML file (`gitops/tenant-claims/<env>/<team>.yaml`, one
`XTenant`) merged to the platform repo via a CODEOWNERS-gated PR. The `tenant-claims-preprod` ArgoCD
Application (in a dedicated `platform-tenants` AppProject whose `clusterResourceWhitelist` admits only
`XTenant`) syncs that directory to the cluster with `selfHeal` + `prune` + ServerSideApply. ArgoCD applies
as the assumed **`ArgoCD` IAM role** — a platform principal excluded from the S1
`restrict-tenant-control-plane` Kyverno backstop that denies `XTenant` creation by tenant principals. (When
Backstage lands — BACK stack P5 — it will scaffold these same claim YAMLs via PR; the delivery mechanism is
pluggable.)

```text
edit gitops/tenant-claims/<env>/<team>.yaml ──PR (CODEOWNERS)──▶ merge
        │
        └──ArgoCD (tenant-claims-<env> app) sync──▶ XTenant CR ──Composition──▶ managed resources
                                                        │                            (K8s + AWS)
   kubectl get xtenant <team>  (SYNCED / READY) ◀───────┘   kubectl get managed | grep <team>
```

**Delete** = remove the team's YAML via PR; ArgoCD's `prune` deletes the `XTenant` and the Composition tears
down every managed resource (both AWS accounts + the cluster) via finalizers.

## Relationship to `teams.hcl`

`teams.hcl` is **no longer the tenant-provisioning source of truth** — the `XTenant` claim is. It now only
feeds two non-provisioning concerns: **app delivery** (`argocd-apps` reads `apps`/`repo_url`) and the
**platform-owned supply-chain policies** (`policy` reads it for `verify_subjects`). A team migrated to a claim
carries `migrated = true`, which withdraws it from the (now-removed) Terragrunt infra loops and tells the
`policy` unit to skip its `restrict-*` guardrails.

To onboard or migrate a team, see the [tenant onboarding runbook](../runbooks/tenant-onboarding.md).

## Verification

```bash
kubectl --context preprod get xtenant <team>                 # SYNCED=True READY=True
kubectl --context preprod get managed | grep <team>          # all aws.upbound.io + Object MRs Ready
aws iam get-role --role-name Pod-team-<team> --profile preprod
aws eks describe-access-entry --cluster-name preprod-use1-eks \
  --principal-arn arn:aws:iam::<preprod>:role/DeveloperAccess-<team> --profile preprod
aws ecr describe-repositories --repository-names team-<team>/<app> --profile platform
```

[#174]: https://github.com/asanexample/platform/issues/174
