# Runbook — Environment AWS access via EKS Pod Identity

How an environment team gets least-privilege AWS access via EKS Pod Identity, how the app consumes it, and how
the mechanism enforces isolation. Mechanism + rationale:
[ADR-041](../adrs/041-pod-identity-for-environment-workloads.md) /
[ADR-047](../adrs/047-pod-identity-standard.md) (Pod Identity is the standard).

> **Provisioning is now the `XTenant` claim.** Environment AWS access is declared in the team's **`XTenant`
> claim** (`aws.serviceAccount` + `aws.policyStatements`) and provisioned by the Crossplane Composition —
> not by editing `teams.hcl` and applying separate units. The previous `s3-shared` and `pod-identity`
> Terragrunt units are **deleted**; the per-team role loops were removed from `iam-roles`. The Pod
> Identity *mechanism* below is unchanged. See [Crossplane Environment API](../architecture/crossplane-environment-api.md)
> and the [environment onboarding runbook](environment-onboarding.md).

---

## Model in one picture

```text
XTenant claim (aws.serviceAccount + aws.policyStatements)
        │
        │  Crossplane Composition (provider-aws iam/eks, ProviderConfig = Pod Identity)
        │
        ├─ Pod-team-<team>  IAM role  (trust pods.eks.amazonaws.com + aws:SourceAccount;
        │                              deny-escalation permissions boundary)
        ├─ RolePolicy        the claim's aws.policyStatements (generic, least-privilege)
        └─ PodIdentityAssociation (cluster, team-<team>, <serviceAccount>) → Pod-team-<team>
                                          │
            app pod (named SA) ───────────┘  EKS Pod Identity agent injects creds (no annotation)
```

Default-deny, by construction: the `Pod-team-<team>` role is named from the team key, grants only what
its own claim declares, and the deny-escalation boundary prevents privilege growth — a team can never
mint or assume another team's role. See ADR-047 "Isolation model".

> **No per-team S3 buckets.** Access to arbitrary AWS is via the claim's generic `aws.policyStatements`.
> The earlier per-team S3 buckets (in the platform account, via the now-deleted `s3-shared` unit) were a
> **demo** of the cross-account bucket-policy pattern and are no longer provisioned. If a team needs a
> bucket, grant it through `policyStatements` against a bucket provisioned separately.

## Granting a team AWS access (platform engineer)

1. **Declare it in the team's `XTenant` claim** (in the `tenant-claims` unit's inputs), under `aws`:

   ```yaml
   spec:
     aws:
       serviceAccount: app-foo            # the named SA the app's pods run as
       policyStatements:                  # generic least-privilege IAM, capped by the deny boundary
         - sid: ReadData
           effect: Allow
           actions: ["s3:GetObject"]
           resources: ["arn:aws:s3:::some-bucket/*"]
   ```

   The Composition grants exactly these statements to `Pod-team-<team>`. A team may only ever grant its
   own role; it cannot name another team's role (the team key is structurally prepended).

2. **Apply the `tenant-claims` unit** (`terragrunt apply`). The Composition reconciles the
   `Pod-team-<team>` role, its RolePolicy, and the Pod Identity association in one pass. (The
   `eks-pod-identity-agent` add-on is installed once cluster-wide by `eks-addons` — not per team.)
   Verify with `kubectl get xtenant <team>` (SYNCED / READY).

3. The app sets `spec.serviceAccountName` to the declared SA and reads via the AWS SDK (creds arrive
   automatically — no annotation, no static keys). See `app-alpha` for a worked example.

## Verifying it works (positive)

```bash
# creds are injected (and the default K8s SA token is NOT — automountServiceAccountToken: false holds):
kubectl exec deploy/<app> -n team-<team> -- env | grep AWS_CONTAINER_CREDENTIALS_FULL_URI
kubectl exec deploy/<app> -n team-<team> -- aws sts get-caller-identity   # -> assumed-role/Pod-team-<team>/...
```

## Cross-team isolation

A pod can only ever assume **its own** team's role: the Pod Identity association binds a specific
`(cluster, namespace, serviceAccount)` triple to `Pod-team-<team>`, and `Pod-team-<team>` grants only the
statements that team's own claim declares (capped by the deny-escalation boundary). A pod in `team-alpha`
has no path to `Pod-team-bravo` — it can't change its association (an AWS API call environments can't make) and
the egress NetworkPolicy blocks IMDS, so it can't steal the node role either.

Static confirmation (no cluster needed):

```bash
# each team's role grants only what its own claim declared:
AWS_PROFILE=preprod aws iam get-role-policy --role-name Pod-team-alpha --policy-name <policy>
# the association binds only that team's namespace + SA:
AWS_PROFILE=preprod aws eks list-pod-identity-associations --cluster-name preprod-use1-eks \
  --namespace team-alpha
```

## Troubleshooting

- **No creds in the pod** — confirm `eks-pod-identity-agent` DaemonSet is Running; confirm the pod's
  `serviceAccountName` matches the claim's `aws.serviceAccount`; confirm an association exists
  (`aws eks list-pod-identity-associations --cluster-name preprod-use1-eks`). If missing, check the
  `XTenant` is READY (`kubectl get xtenant <team>`) — the Composition provisions the association.
- **AccessDenied on an action the team should have** — confirm the claim's `aws.policyStatements` actually
  grant it (the deny-escalation boundary also caps what can be granted), re-apply the `tenant-claims`
  unit, and confirm the `Pod-team-<team>` RolePolicy reconciled (`kubectl get managed | grep <team>`).
- **Pod gets no AWS creds / SDK hangs then DNS-fails** — the SDK can't reach the Pod Identity agent.
  Cilium classifies the agent (`169.254.170.23:80`) as the **`host`** entity, which CIDR egress rules
  don't match; the Composition's `allow-pod-identity-egress` CiliumNetworkPolicy
  (`toEntities: ["host"]`, port 80) grants it. Confirm with `cilium monitor --type drop` on the node —
  a `…->host: …169.254.170.23:80 … Policy denied` means that CNP is missing/not applied. (IMDS stays
  blocked by the node's IMDSv2 hop-limit=1, not by this rule.)
- **Environment tried to set an `eks.amazonaws.com/role-arn` annotation** — denied by
  `disallow-irsa-annotation-cross-team` (by design — environments use Pod Identity, not IRSA).
