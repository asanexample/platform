# Runbook: Secrets Management Operations

> **Severity:** Low (routine operations)
> **On-call scope:** Infrastructure / Platform Engineering
> **Module path:** `infra/modules/external-secrets/`, `infra/live/aws/platform/us-east-1/platform/external-secrets/`
>
> **Last reviewed:** 2026-06-01

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Creating a New Platform Secret](#creating-a-new-platform-secret)
3. [Creating a New App Team Secret](#creating-a-new-app-team-secret)
4. [Verifying ESO Sync Status](#verifying-eso-sync-status)
5. [Debugging a Failed Sync](#debugging-a-failed-sync)
6. [Break-Glass: Reading a Secret for Debugging](#break-glass-reading-a-secret-for-debugging)
7. [Listing All Secrets](#listing-all-secrets)
8. [Deleting a Secret](#deleting-a-secret)

---

## Architecture Overview

Secrets flow from AWS Secrets Manager into Kubernetes pods through a
declarative sync pipeline. The External Secrets Operator (ESO) runs in-cluster
and uses IRSA to authenticate to Secrets Manager without long-lived credentials.

```text
AWS Secrets Manager          Kubernetes Cluster
┌──────────────────┐        ┌──────────────────────────────────┐
│ platform/        │  IRSA  │                                  │
│   service/       │◄───────│  ESO Controller                  │
│     secret-name  │  (STS) │    ↓ fetches secret value        │
└──────────────────┘        │  ExternalSecret CRD              │
                            │    ↓ declares source + target    │
                            │  Kubernetes Secret               │
                            │    ↓ mounted into pod            │
                            │  Pod                             │
                            └──────────────────────────────────┘
```

The full chain: **AWS Secrets Manager** -> **IRSA (STS AssumeRoleWithWebIdentity)** ->
**ESO Controller** -> **ExternalSecret CRD** -> **Kubernetes Secret** -> **Pod**.

See [ADR-019](../adrs/019-external-secrets-operator.md) for the decision to adopt ESO
and [ADR-025](../adrs/025-secret-naming-convention.md) for the naming convention.

---

## Creating a New Platform Secret

Platform secrets use the naming convention `platform/{service}/{secret-name}`
(see [ADR-025](../adrs/025-secret-naming-convention.md)). All segments are
lowercase and hyphen-delimited.

### Step 1: Create the secret in AWS Secrets Manager

```bash
aws sso login --profile platform

# Simple string secret
AWS_PROFILE=platform aws secretsmanager create-secret \
  --name platform/myservice/api-key \
  --secret-string '<VALUE>' \
  --region us-east-1

# JSON secret (multiple key-value pairs)
AWS_PROFILE=platform aws secretsmanager create-secret \
  --name platform/myservice/credentials \
  --secret-string '{"key1":"val1","key2":"val2"}' \
  --region us-east-1
```

### Step 2: Tag the secret

```bash
AWS_PROFILE=platform aws secretsmanager tag-resource \
  --secret-id platform/myservice/api-key \
  --tags Key=Environment,Value=platform Key=ManagedBy,Value=manual Key=Owner,Value="Platform Team" \
  --region us-east-1
```

### Step 3: Create an ExternalSecret CRD

Create a manifest that tells ESO to sync the secret into Kubernetes:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: my-secret
  namespace: my-namespace
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: my-k8s-secret
    creationPolicy: Owner
  data:
  - secretKey: api-key
    remoteRef:
      key: platform/myservice/api-key
```

For JSON secrets, use `remoteRef.property` to extract individual keys:

```yaml
  data:
  - secretKey: username
    remoteRef:
      key: platform/myservice/credentials
      property: key1
  - secretKey: password
    remoteRef:
      key: platform/myservice/credentials
      property: key2
```

### Step 4: Apply

Apply via ArgoCD (preferred) by committing the manifest to the app's repo, or
directly for testing:

```bash
kubectl apply -f external-secret.yaml
```

---

## Creating a New App Team Secret

> **Note:** This section describes the **target model** for per-namespace environment *secrets* via ESO,
> which is **not yet deployed** (ADR-024 Implementation Status). Today, ESO secrets are platform-scoped
> (the `aws-secrets-manager` ClusterSecretStore runs on both platform and preprod). Environment access to
> AWS *resources* (S3, etc.) is already live but uses **EKS Pod Identity**, not ESO — see
> [ADR-041](../adrs/041-pod-identity-for-environment-workloads.md) and the
> [environment AWS access runbook](environment-aws-access-pod-identity.md).

App team secrets use the naming convention `{namespace}/{service}/{secret-name}`,
where the namespace maps to the team's Kubernetes namespace.

### Prerequisites

- The secret must be created in the correct AWS account (preprod or prod, not
  platform)
- The team must have a namespace-scoped `SecretStore` in their namespace,
  configured with an IRSA role scoped to their secret path prefix
- The IRSA role's IAM policy must allow
  `secretsmanager:GetSecretValue` on `arn:aws:secretsmanager:*:${account_id}:secret:{namespace}/*`

### Steps

```bash
# Create the secret in the workload account
AWS_PROFILE=preprod aws secretsmanager create-secret \
  --name payments/stripe/api-key \
  --secret-string '<VALUE>' \
  --region us-east-1
```

The ExternalSecret CRD references the namespace-scoped SecretStore instead
of the ClusterSecretStore:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: stripe-api-key
  namespace: payments
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: payments-secret-store
    kind: SecretStore
  target:
    name: stripe-api-key
    creationPolicy: Owner
  data:
  - secretKey: api-key
    remoteRef:
      key: payments/stripe/api-key
```

---

## Verifying ESO Sync Status

### Check all ExternalSecrets

```bash
kubectl get externalsecret -A
```

The `STATUS` column shows the sync state:

| Status | Meaning |
|--------|---------|
| `SecretSynced` | Secret was successfully fetched and the K8s Secret is up to date |
| `SecretSyncedError` | ESO attempted to sync but encountered an error |

### Inspect a specific ExternalSecret

```bash
kubectl describe externalsecret <name> -n <namespace>
```

Check the `Events` section for error details.

### Verify the Kubernetes Secret exists

```bash
kubectl get secret <target-name> -n <namespace>
```

If the secret exists but the ExternalSecret shows an error, the K8s Secret
may contain stale data from a previous successful sync.

### Common errors

- **IAM permission denied:** The IRSA role does not have
  `secretsmanager:GetSecretValue` for the secret's ARN. Check that the
  secret path matches the IAM policy's resource pattern.
- **Secret not found:** The `remoteRef.key` path is wrong, or the secret
  is in a different AWS account than the one the SecretStore is configured for.
- **Refresh interval not elapsed:** ESO only fetches on the `refreshInterval`
  cadence. A newly created secret in Secrets Manager won't appear in
  Kubernetes until the next refresh cycle.

---

## Debugging a Failed Sync

### Check ESO controller logs

```bash
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets --tail=100
```

Look for errors related to the specific secret path or STS assume-role failures.

### Verify IRSA configuration

```bash
kubectl describe sa external-secrets -n external-secrets
```

Confirm the `eks.amazonaws.com/role-arn` annotation is present and points to
the correct IAM role.

### Verify the IAM policy

```bash
AWS_PROFILE=platform aws iam get-role-policy \
  --role-name <eso-irsa-role-name> \
  --policy-name secrets-access
```

Confirm the policy grants `secretsmanager:GetSecretValue` on an ARN pattern
that matches the secret path (e.g., `arn:aws:secretsmanager:*:<PLATFORM_ACCOUNT_ID>:secret:platform/*`).

### Verify the secret exists in Secrets Manager

```bash
AWS_PROFILE=platform aws secretsmanager get-secret-value \
  --secret-id platform/myservice/api-key \
  --region us-east-1
```

If this fails with `ResourceNotFoundException`, the secret path in the
ExternalSecret CRD does not match any secret in Secrets Manager.

---

## Break-Glass: Reading a Secret for Debugging

Use the **PlatformAdmin** role, which has `secretsmanager:GetSecretValue`
scoped to `platform/*`.

### Simple string secret

```bash
aws sso login --profile platform

AWS_PROFILE=platform aws secretsmanager get-secret-value \
  --secret-id platform/myservice/api-key \
  --region us-east-1
```

### JSON secret (pretty-printed)

```bash
AWS_PROFILE=platform aws secretsmanager get-secret-value \
  --secret-id platform/myservice/credentials \
  --query SecretString --output text \
  --region us-east-1 | jq
```

> **IMPORTANT:** All `GetSecretValue` calls are logged in CloudTrail. Every
> access is attributable to the caller's IAM identity. Use this only when
> necessary for debugging -- do not routinely read production secrets.

---

## Listing All Secrets

### Secrets in AWS Secrets Manager (per account)

```bash
AWS_PROFILE=platform aws secretsmanager list-secrets \
  --region us-east-1 \
  --query 'SecretList[].Name' --output table
```

### ExternalSecrets in Kubernetes

```bash
kubectl get externalsecret -A
```

### Finding orphaned secrets

Compare the two lists to identify secrets in Secrets Manager that have no
corresponding ExternalSecret referencing them:

```bash
# List all SM secret names
AWS_PROFILE=platform aws secretsmanager list-secrets \
  --region us-east-1 \
  --query 'SecretList[].Name' --output text | tr '\t' '\n' | sort > /tmp/sm-secrets.txt

# List all remoteRef.key values from ExternalSecrets
kubectl get externalsecret -A -o jsonpath='{range .items[*]}{range .spec.data[*]}{.remoteRef.key}{"\n"}{end}{end}' | sort > /tmp/es-refs.txt

# Show SM secrets with no ExternalSecret reference
comm -23 /tmp/sm-secrets.txt /tmp/es-refs.txt
```

---

## Deleting a Secret

### Terraform-managed secrets

Remove the resource from Terraform and apply. The secret enters a recovery
window (controlled by `recovery_window_in_days`, default 7 days) before
permanent deletion.

### Manually-created secrets

```bash
AWS_PROFILE=platform aws secretsmanager delete-secret \
  --secret-id platform/myservice/api-key \
  --recovery-window-in-days 7 \
  --region us-east-1
```

> **NEVER** use `--force-delete-without-recovery` in production. The recovery
> window allows you to cancel a mistaken deletion with
> `aws secretsmanager restore-secret`.

### Clean up the Kubernetes side

Delete the corresponding ExternalSecret CRD. Because `creationPolicy: Owner`
is set, deleting the ExternalSecret also deletes the Kubernetes Secret it
created:

```bash
kubectl delete externalsecret <name> -n <namespace>
```

If the ExternalSecret used `creationPolicy: Merge` or `None`, the Kubernetes
Secret will persist after the ExternalSecret is deleted and must be removed
manually:

```bash
kubectl delete secret <target-name> -n <namespace>
```
