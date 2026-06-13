# Crossplane Environment API

How environments are provisioned on this platform. An environment is a single declarative **`XEnvironment`
claim** (`platform.refplat.org/v1alpha3`); a Crossplane **Composition** reconciles it into the complete
environment footprint — Kubernetes, AWS (workload account), and cross-account ECR. This is the **current, sole**
provisioning path (ADR-067, the v3 Team → Product → Service → Environment model). The retired v2 path (the
`XTenant` claim + `crossplane-tenant` chart, where `team == environment`) is gone.

See also: [ADR-046](../adrs/046-back-stack-for-developer-self-service.md) (adopt the BACK stack),
[ADR-048](../adrs/048-federated-per-cluster-crossplane.md) (federated topology),
[ADR-047](../adrs/047-pod-identity-as-aws-identity-standard.md) (Pod Identity standard).

## Federated topology

Crossplane is **federated — one instance per cluster**, not a central hub reaching into every account. Each
workload cluster runs its own Crossplane and provisions its **own** environments locally, using its own EKS Pod
Identity to authenticate the providers. The single cross-account hop is **ECR**: environment image repos live in
the platform account, so the provider-aws `ecr` provider assumes the platform `crossplane-ecr-provisioner`
role (`assumeRoleChain`) for those resources only.

```text
            platform account                         preprod cluster (its own Crossplane)
  ┌───────────────────────────────┐      ┌────────────────────────────────────────────────┐
  │  crossplane-ecr-provisioner    │◀─────│ provider-aws-ecr  (assumeRoleChain, ECR only)   │
  │  ECR repos: team-*/*           │      │ provider-aws-iam/eks (Pod Identity, local)      │
  └───────────────────────────────┘      │ provider-kubernetes  (in-cluster)               │
                                          │ XEnvironment XRD + Composition + functions      │
                                          └────────────────────────────────────────────────┘
```

The control plane (Crossplane core, providers, XRD/Composition) is installed by the
[`crossplane`](../../infra/modules/crossplane/) Terragrunt module as a normal add-on unit. Claims are
delivered separately (below).

## The `XEnvironment` claim

`apiVersion: platform.refplat.org/v1alpha3`, `kind: XEnvironment`, **cluster-scoped** (Crossplane v2 XR). The
spec is the environment-facing contract — no infra constants leak into it:

| Field | Required | Purpose |
| ----- | -------- | ------- |
| `team` | yes | Team key; the envelope authority (the git-native `Team` CR, ADR-063) caps tiers/stages/quota/locations |
| `product` | yes | Owning Product (the `Product` CR — repo/domains/tenancy); drives the namespace and per-product resource names |
| `stage` | yes | `dev`/`test`/`uat`/`staging`/`prod` — the deployment stage of this environment |
| `customer` | — (per-customer prod/uat only) | Customer key; appended to the namespace for per-customer isolation |
| `tier` | — (default `standard`) | `standard`/`elevated`/`pci`/`hipaa` — the hardening profile (isolation floor + recovery + availability) |
| `isolation.compute` | — (resolved from Product/tier) | The graduated compute dial: `shared-namespace`/`dedicated-namespace`/`dedicated-nodes`/`dedicated-cluster`/`dedicated-account` |
| `residency.allowedLocations` | — (default `["*"]`) | Jurisdiction or `cloud:region`; must be ⊆ the Team's allowed locations |
| `quota` | — (defaults match the old environment module) | `cpu`/`memory`/`pods`/`services`/`loadbalancers`/`pvcs`/`storage` |
| `domains` | — | Vanity/custom aliases (`[]` of `{ host, canonical?, dns? }`, ADR-061). Unioned with the implicit generated host into `restrict-route-hostnames`; the generated host is never declared |
| `lifecycle.phase` | — (default `active`) | `active`/`suspended`/`decommissioning` — the reversible suspend zeroes the ResourceQuota (ADR-062) |
| `services` | — | Map `<svc> → { serviceAccount, preview, image, permissions.aws.policyStatements }`; each service gets an ECR repo `team-<team>/<product>-<svc>` + a Pod-Identity role |

The namespace (and `metadata.name`) is `<team>-<product>-<stage>` (pooled) or
`<team>-<product>-<customer>-<stage>` (per-customer), truncated-and-hashed on the 63-char limit. Live claims are
YAML files in `gitops/environments/<team>/<product>/<stage>[-<customer>].yaml` (one `XEnvironment` per file).
The sibling **`Product`** (`gitops/products/<team>/<product>.yaml`) and **`Team`** (git-native, ADR-063)
registries are the envelope and delivery authorities; cross-team grants are **`AccessGrant`** CRs.

### `status.domains` — the ingress state machine (ADR-061 Phase 2)

The Composition writes `status.domains[]` (`{ host, state, mode, reason, message?, dnsTarget?,
lastTransitionTime? }`) — one entry per generated canonical host + each `spec.domains` alias — and the
`restrict-route-hostnames` allow-list admits a host **only while its entry is `Active`**. Verification is the
security boundary: an environment cannot route a domain whose state is not yet `Active`.

- **Generated host** (`<product>-<team>-<stage>.<baseDomain>`, e.g. `demo-alpha-dev.preprod.aws.refplat.org`) +
  tier-1/2 aliases (host under `.<baseDomain>`, our wildcard cert) → `Active` immediately (platform-owned).
- **Tier-3 external** hosts → `Pending` (`AwaitingProvisioning`) and **not admitted** until **Phase 2b** wires
  the per-domain DNS/cert (then they transition `Pending → … → Active`, observed from the backing resources —
  the [spike](../spikes/adr-061-phase2-ingress-spike.md) proved this runs inside `function-go-templating`, no
  controller). 2a populates `host/state/mode/reason` only.

## What the Composition provisions

The Composition (`infra/modules/crossplane/charts/environment-api/files/composition-v3.yaml`, mode `Pipeline`)
renders, from one claim:

**Kubernetes** (via `provider-kubernetes` `Object`s):

- Namespace `<team>-<product>-<stage>[-<customer>]` (labeled `platform.refplat.org/{team,product,stage,customer?,tier,mode}` + PSA baseline/restricted), ResourceQuota, LimitRange
- default-deny + allow-DNS/allow-gateway NetworkPolicies, CiliumNetworkPolicies (gateway/Envoy `fromEntities: [ingress]` + Pod-Identity egress)
- `<ns>:developers` RoleBinding (binds the `environment-developer` ClusterRole — ADR-039)
- per-namespace Kyverno `restrict-images-<ns>` + `restrict-route-hostnames-<ns>` ClusterPolicies

**AWS — workload account** (via `provider-aws` `iam`/`eks`, ProviderConfig `default` = Pod Identity):

- per service: `Pod-<team>-<product>-[<customer>-]<stage>-<svc>` IAM role (trust `pods.eks.amazonaws.com` +
  `aws:SourceAccount`; capped by the **`environment-permissions-boundary-<cluster>`** boundary; `Team`/`Customer`
  tags) + its RolePolicy (the service's `permissions.aws.policyStatements`, deny-set-validated)
- EKS Pod Identity association `(cluster, <ns>, services.<svc>.serviceAccount) → Pod-<team>-<product>-…-<svc>`
- `DeveloperAccess-<team>` IAM role (trust = the team's `Dev-<team>` SSO permission set in mgmt + workload
  accounts) + EKS **access entry** mapping it to the `<ns>:developers` group

**AWS — platform account** (via `provider-aws` `ecr`, ProviderConfig `platform-ecr` = assumeRoleChain):

- `team-<team>/<product>-<svc>` ECR repo per service (`IMMUTABLE_WITH_EXCLUSION` for cosign `sha256-*` tags,
  scan-on-push) plus a cross-account RepositoryPolicy (pull for the preprod and prod account roots)

**Not** provisioned by the claim — these stay platform-owned in the [`policy`](../../infra/modules/policy/)
module for **all** products (an environment must not declare its own signature trust root): the cosign/SLSA
`verify-images-team-<team>` + `verify-attestations-team-<team>` policies. The `policy` unit skips only the
per-product `restrict-*` guardrails for migrated teams (`migrated_teams` input), since the Composition owns
those. This **supply-chain split** — guardrails in the claim, trust roots in the platform — is deliberate
(ADR-014/046).

## Composition pipeline

```text
load-environment   function-environment-configs   merges the platform-cluster-config EnvironmentConfig
       │                                           into the pipeline context (cluster constants)
render-resources   function-go-templating          renders all of the above from spec + context
       │
ready              function-auto-ready              marks the XR Ready when its resources are Ready
```

**Cluster constants** (ECR registry, workload + management account IDs, cluster name, the permissions-boundary
ARN, the cross-account pull accounts, `baseDomain`, the ECR ProviderConfig name) are **not** in the claim —
they're injected via a Helm-templated **`EnvironmentConfig`** (`platform-cluster-config`) read by the go-template
as `index .context "apiextensions.crossplane.io/environment"`. This keeps the claim API clean and per-cluster
config out of the environment-facing spec. The Composition itself ships **raw** (`.Files.Get`) so Helm doesn't
try to process its inline go-template `{{ }}`.

## Claim delivery & lifecycle

Claims are **GitOps-delivered**: each is a YAML file (`gitops/environments/<team>/<product>/<stage>[-<customer>].yaml`,
one `XEnvironment`) merged to the platform repo via a CODEOWNERS-gated PR. The `environments-preprod` ArgoCD
Application (in a dedicated `platform-environments` AppProject whose `clusterResourceWhitelist` admits only
`XEnvironment`) syncs that directory to the cluster with `selfHeal` + `prune` + ServerSideApply. ArgoCD applies
as the assumed **`ArgoCD` IAM role** — a platform principal excluded from the S1
`restrict-environment-control-plane` Kyverno backstop that denies `XEnvironment` creation by environment
principals. (Backstage — BACK stack P5 — scaffolds these same claim YAMLs via PR; the delivery mechanism is
pluggable.)

```text
edit gitops/environments/<team>/<product>/<stage>.yaml ──PR (CODEOWNERS)──▶ merge
        │
        └──ArgoCD (environments-<env> app) sync──▶ XEnvironment CR ──Composition──▶ managed resources
                                                        │                              (K8s + AWS)
   kubectl get xenvironment <name>  (SYNCED / READY) ◀──┘   kubectl get managed | grep <name>
```

**Delete** = remove the environment's YAML via PR; ArgoCD's `prune` deletes the `XEnvironment` and the
Composition tears down every managed resource (both AWS accounts + the cluster) via finalizers.

## Catalog projection (Backstage)

The same claim files are the source of truth for the **Backstage software catalog** (BACK stack Phase 2.3a).
A custom backend entity provider — `plugins/platform-projection` in the [backstage repo](https://github.com/asanexample/backstage) —
reads `gitops/environments/**/*.yaml` (plus the `Product`/`Team` registries) from git via the **read-only
GitHub App** (no AWS, no cluster credential) on a 30-minute schedule and projects each `XEnvironment` into
catalog entities ([ADR-049] forward-compat model):

| Catalog entity | From the claim | Notes |
|---|---|---|
| `Group <team>` | `spec.team` | `spec.type: team`; supersedes the seed Group |
| `System <name>` | `metadata.name` | `owner: group:<team>`; carries **`stage`/`tier`** as first-class attributes; `links` from the generated host + `spec.domains` |
| `Resource`s | the Composition's footprint | a **curated** mirror — the `<team>-<product>-<stage>` namespace + quota, `ecr-team-<team>-<product>-<svc>` per service, `Pod-<team>-<product>-…-<svc>` + `DeveloperAccess-<team>` IAM roles, the `restrict-images`/`restrict-route-hostnames` Kyverno policies; each `owner: group:<team>`, `system: <name>` |

App `Component`s (discovered separately from the app repos' `catalog-info.yaml`) set `spec.system: <name>`, so
each environment System *contains* its service. The projection is **authoritative** for Groups/Systems/Resources;
the discovered Components only self-assert ownership (acceptable trust posture for an internal read-only portal).
The Resource set is deterministic and curated — widen the mapping in `provider.ts` if a deeper audit lens is
wanted. The projection emits entities directly (provider roots), so it bypasses `catalog.rules`; a trusted
`url` pattern branch is kept belt-and-suspenders.

## Relationship to the git-native registries

The `XEnvironment` claim is the **sole environment-provisioning source of truth**; the retired v2 app-delivery
`teams.hcl` is gone. The two non-provisioning concerns it once fed now derive from the git-native CRs:
**app delivery** (`argocd-apps` reads the `Product` registry for `repo`/domains) and the **platform-owned
supply-chain policies** (`policy` reads them for `verify_subjects`). A team migrated to the v3 model carries
`migrated = true`, which withdraws it from the (now-removed) Terragrunt infra loops and tells the `policy` unit
to skip its `restrict-*` guardrails.

To onboard or migrate a team, see the [environment onboarding runbook](../runbooks/environment-onboarding.md).

## Verification

```bash
kubectl --context preprod get xenvironment <name>           # SYNCED=True READY=True
kubectl --context preprod get managed | grep <name>          # all aws.upbound.io + Object MRs Ready
aws iam get-role --role-name Pod-<team>-<product>-<stage>-<svc> --profile preprod
aws eks describe-access-entry --cluster-name preprod-use1-eks \
  --principal-arn arn:aws:iam::<preprod>:role/DeveloperAccess-<team> --profile preprod
aws ecr describe-repositories --repository-names team-<team>/<product>-<svc> --profile platform
```

[ADR-049]: ../adrs/049-tenant-model-team-tenant-zone.md
