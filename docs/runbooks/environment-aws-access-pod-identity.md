# Runbook — Environment AWS access via EKS Pod Identity

How an environment's Service gets least-privilege AWS access via EKS Pod Identity, how the app consumes it, and
how the mechanism enforces isolation. Mechanism + rationale:
[ADR-041](../adrs/041-pod-identity-for-tenant-workloads.md) /
[ADR-047](../adrs/047-pod-identity-as-aws-identity-standard.md) (Pod Identity is the standard).

> **Provisioning is now the `XEnvironment` claim.** AWS access is declared **per Service** on the
> `XEnvironment` claim (`services.<svc>.serviceAccount` + `services.<svc>.permissions.aws.policyStatements`) and
> provisioned by the Crossplane Composition — not by editing `teams.hcl` and applying separate units. The
> previous `s3-shared` and `pod-identity` Terragrunt units are **deleted**; the per-team role loops were removed
> from `iam-roles`. The Pod Identity *mechanism* below is unchanged. See
> [Crossplane Environment API](../architecture/crossplane-environment-api.md) and the
> [environment onboarding runbook](environment-onboarding.md).

---

## Model in one picture

```text
XEnvironment claim (services.<svc>.serviceAccount + .permissions.aws.policyStatements)
        │
        │  Crossplane Composition (provider-aws iam/eks, ProviderConfig = Pod Identity)
        │
        ├─ Pod-<team>-<product>-[<customer>-]<stage>-<svc>  IAM role  (trust pods.eks.amazonaws.com +
        │                              aws:SourceAccount; environment-permissions-boundary)
        ├─ RolePolicy        the Service's permissions.aws.policyStatements (generic, least-privilege)
        └─ PodIdentityAssociation (cluster, <team>-<product>-<stage> ns, <serviceAccount>) → that role
                                          │
            app pod (named SA) ───────────┘  EKS Pod Identity agent injects creds (no annotation)
```

Default-deny, by construction: the role is named from the (team, product, stage, service) tuple, grants only what
that Service's claim declares, and the permissions boundary prevents privilege growth — a Service can never
mint or assume another environment's role. See ADR-047 "Isolation model".

> **No per-team S3 buckets.** Access to arbitrary AWS is via the Service's generic `permissions.aws.policyStatements`.
> The earlier per-team S3 buckets (in the platform account, via the now-deleted `s3-shared` unit) were a
> **demo** of the cross-account bucket-policy pattern and are no longer provisioned. If a Service needs a
> bucket, grant it through `policyStatements` against a bucket provisioned separately.

## Granting a Service AWS access (platform engineer)

1. **Declare it on the `XEnvironment` claim** (in `gitops/environments/<team>/<product>/<stage>.yaml`), under the
   Service's `permissions.aws`:

   ```yaml
   spec:
     services:
       web:
         serviceAccount: app-foo            # the named SA the app's pods run as
         permissions:
           aws:
             policyStatements:              # generic least-privilege IAM, capped by the boundary
               - sid: ReadData
                 effect: Allow
                 actions: ["s3:GetObject"]
                 resources: ["arn:aws:s3:::some-bucket/*"]
   ```

   The Composition grants exactly these statements to that Service's `Pod-<team>-<product>-[<customer>-]<stage>-<svc>`
   role. A claim may only ever grant its own Services' roles; it cannot name another environment's role (the
   tuple is structurally prepended).

2. **Sync the claim** (open a PR; ArgoCD's per-Product ApplicationSet syncs it). The Composition reconciles the
   `Pod-…-<svc>` role, its RolePolicy, and the Pod Identity association in one pass. (The
   `eks-pod-identity-agent` add-on is installed once cluster-wide by `eks-addons` — not per environment.)
   Verify with `kubectl get xenvironment <name>` (SYNCED / READY).

3. The app sets `spec.serviceAccountName` to the declared SA and reads via the AWS SDK (creds arrive
   automatically — no annotation, no static keys). See the `alpha-shop` app repo for a worked example.

## Verifying it works (positive)

```bash
NS=<team>-<product>-<stage>
# creds are injected (and the default K8s SA token is NOT — automountServiceAccountToken: false holds):
kubectl exec deploy/<app> -n $NS -- env | grep AWS_CONTAINER_CREDENTIALS_FULL_URI
kubectl exec deploy/<app> -n $NS -- aws sts get-caller-identity   # -> assumed-role/Pod-<team>-<product>-<stage>-<svc>/...
```

## Cross-environment isolation

A pod can only ever assume **its own** Service's role: the Pod Identity association binds a specific
`(cluster, namespace, serviceAccount)` triple to `Pod-<team>-<product>-[<customer>-]<stage>-<svc>`, and that role
grants only the statements that Service's own claim declares (capped by the permissions boundary). A pod in
`alpha-shop-dev` has no path to a `bravo-*` role — it can't change its association (an AWS API call environment
workloads can't make) and the egress NetworkPolicy blocks IMDS, so it can't steal the node role either.

Static confirmation (no cluster needed):

```bash
# each Service's role grants only what its own claim declared:
AWS_PROFILE=preprod aws iam get-role-policy --role-name Pod-alpha-shop-dev-web --policy-name <policy>
# the association binds only that environment's namespace + SA:
AWS_PROFILE=preprod aws eks list-pod-identity-associations --cluster-name preprod-use1-eks \
  --namespace alpha-shop-dev
```

## Troubleshooting

- **No creds in the pod** — confirm `eks-pod-identity-agent` DaemonSet is Running; confirm the pod's
  `serviceAccountName` matches the Service's `serviceAccount`; confirm an association exists
  (`aws eks list-pod-identity-associations --cluster-name preprod-use1-eks`). If missing, check the
  `XEnvironment` is READY (`kubectl get xenvironment <name>`) — the Composition provisions the association.
- **AccessDenied on an action the Service should have** — confirm the Service's `permissions.aws.policyStatements`
  actually grant it (the permissions boundary also caps what can be granted), re-sync the claim, and confirm the
  `Pod-…-<svc>` RolePolicy reconciled (`kubectl get managed | grep <name>`).
- **Pod gets no AWS creds / SDK hangs then DNS-fails** — the SDK can't reach the Pod Identity agent.
  Cilium classifies the agent (`169.254.170.23:80`) as the **`host`** entity, which CIDR egress rules
  don't match; the Composition's `allow-pod-identity-egress` CiliumNetworkPolicy
  (`toEntities: ["host"]`, port 80) grants it. Confirm with `cilium monitor --type drop` on the node —
  a `…->host: …169.254.170.23:80 … Policy denied` means that CNP is missing/not applied. (IMDS stays
  blocked by the node's IMDSv2 hop-limit=1, not by this rule.)
- **Environment workload tried to set an `eks.amazonaws.com/role-arn` annotation** — denied by
  `disallow-irsa-annotation-cross-team` (by design — environment workloads use Pod Identity, not IRSA;
  IRSA is platform-only).
