# Runbook — Tenant AWS access via EKS Pod Identity

How a tenant team gets least-privilege, **isolated** AWS access (e.g. an S3 bucket), how the app
consumes it, and how to verify the cross-team isolation holds. Mechanism + rationale:
[ADR-041](../adrs/041-pod-identity-for-tenant-workloads.md).

---

## Model in one picture

```text
teams.hcl (aws block, platform-controlled)
        │
        ├─ iam-roles unit   → Pod-team-<team>  (trust pods.eks.amazonaws.com; S3 identity policy
        │                                        scoped to <org>-team-<team>-* by construction)
        ├─ s3-shared unit   → <org>-team-<team>-<suffix> bucket (platform acct) + bucket policy
        │                       granting ONLY Pod-team-<team>  (cross-account)
        └─ pod-identity unit → association (cluster, team-<team>, <serviceAccount>) → Pod-team-<team>
                                          │
            app pod (named SA) ───────────┘  EKS Pod Identity agent injects creds (no annotation)
```

Default-deny, by construction: a team's role and its bucket's reader are **both** derived from the team
key, so a team can only ever access `<org>-team-<itself>-*`. See ADR-041 "Isolation model".

## Granting a team AWS access (platform engineer)

1. **Declare it in `teams.hcl`** (`infra/live/aws/preprod/us-east-1/platform/teams.hcl`), under the
   team's `aws` block:

   ```hcl
   aws = {
     service_account = "app-foo"            # the named SA the app's pods run as
     s3 = { "data" = { access = "read", prefix = "" } }   # -> <org>-team-<team>-data
   }
   ```

   `s3` keys are **suffixes** — the full bucket name is `${org_name}-team-<team>-<suffix>`. A team may
   only declare buckets for itself (the team key is structurally prepended); do **not** hand a team a
   bucket named for another team.

2. **Apply, in this order** (gated `plan → apply`; roles must exist before the bucket policy references
   them):
   1. preprod `iam-roles` — creates `Pod-team-<team>` (+ S3 identity policy).
   2. platform `s3-shared` — creates the bucket + cross-account bucket policy → `Pod-team-<team>`.
   3. preprod `eks-addons` — installs `eks-pod-identity-agent` (one-time).
   4. preprod `pod-identity` — creates the association.

3. The app sets `spec.serviceAccountName` to the declared SA and reads via the AWS SDK (creds arrive
   automatically — no annotation, no static keys). See `app-alpha` for a worked example.

## Verifying it works (positive)

```bash
# creds are injected (and the default K8s SA token is NOT — automountServiceAccountToken: false holds):
kubectl exec deploy/<app> -n team-<team> -- env | grep AWS_CONTAINER_CREDENTIALS_FULL_URI
kubectl exec deploy/<app> -n team-<team> -- aws sts get-caller-identity   # -> assumed-role/Pod-team-<team>/...
# app reads its bucket:
curl -s https://<app-host>/data?key=hello.txt        # -> 200 + object content
```

## The cross-team isolation test (the "money shot")

Prove team-alpha **cannot** read team-bravo's bucket. Using app-alpha's `/data?bucket=` override (the app
asks for a bucket it isn't granted):

```bash
curl -s https://demo.preprod.aws.refplat.org/data?bucket=asanexample-team-bravo-data | jq
# -> 502 + "error": "... AccessDenied: Access Denied"
```

This is denied **twice over**: alpha's identity policy has no statement for `asanexample-team-bravo-data`
(IAM default-deny), **and** that bucket's policy trusts only `Pod-team-bravo` (resource default-deny).
Either alone denies; both make it structural.

Static confirmation (no cluster needed):

```bash
# alpha's role can only name its own bucket:
AWS_PROFILE=preprod aws iam get-role-policy --role-name Pod-team-alpha --policy-name s3-access \
  | grep -o 'asanexample-team-[a-z]*-data'        # -> only asanexample-team-alpha-data
# bravo's bucket trusts only Pod-team-bravo:
AWS_PROFILE=platform aws s3api get-bucket-policy --bucket asanexample-team-bravo-data \
  | jq -r '.Policy' | grep -o 'Pod-team-[a-z]*'   # -> only Pod-team-bravo
```

## Troubleshooting

- **No creds in the pod** — confirm `eks-pod-identity-agent` DaemonSet is Running; confirm the pod's
  `serviceAccountName` matches the association's `service_account`; confirm an association exists
  (`aws eks list-pod-identity-associations --cluster-name preprod-use1-eks`).
- **AccessDenied on the team's OWN bucket** — both the identity policy (iam-roles) and the bucket policy
  (s3-shared) must be applied; if you applied `s3-shared` before `iam-roles`, re-apply `s3-shared` so the
  bucket policy resolves the role principal.
- **Pod gets no AWS creds / SDK hangs then DNS-fails** — the SDK can't reach the Pod Identity agent.
  Cilium classifies the agent (`169.254.170.23:80`) as the **`host`** entity, which CIDR egress rules
  don't match; the `tenant` module's `allow-pod-identity-egress` CiliumNetworkPolicy
  (`toEntities: ["host"]`, port 80) grants it. Confirm with `cilium monitor --type drop` on the node —
  a `…->host: …169.254.170.23:80 … Policy denied` means that CNP is missing/not applied. (IMDS stays
  blocked by the node's IMDSv2 hop-limit=1, not by this rule.)
- **Tenant tried to set an `eks.amazonaws.com/role-arn` annotation** — denied by
  `disallow-irsa-annotation-cross-team` (by design — tenants use Pod Identity, not IRSA).
