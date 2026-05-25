# Runbook: Secret Rotation Procedures

> **Severity:** Medium (routine rotation) to Critical (compromised secret)
> **On-call scope:** Infrastructure / Platform Engineering
> **Module path:** `infra/live/aws/platform/us-east-1/platform/tailscale-admin/`,
> `infra/live/aws/platform/us-east-1/platform/tailscale/`,
> `infra/live/aws/platform/us-east-1/platform/cloudflare-dns/`,
> `infra/live/aws/platform/us-east-1/platform/argocd/`
>
> **Last reviewed:** 2026-05-24

---

## Table of Contents

1. [Cloudflare API Token Rotation](#1-cloudflare-api-token-rotation)
2. [Tailscale API Key Rotation](#2-tailscale-api-key-rotation)
3. [Tailscale OAuth Client Rotation](#3-tailscale-oauth-client-rotation)
4. [ArgoCD SSO CA Certificate Renewal](#4-argocd-sso-ca-certificate-renewal)
5. [Emergency: Compromised Secret Response](#5-emergency-compromised-secret-response)
6. [Proactive: Tracking Secret Expiry](#6-proactive-tracking-secret-expiry)

---

## 1. Cloudflare API Token Rotation

The Cloudflare API token authenticates the Cloudflare Terraform provider
used by the `cloudflare-dns` unit. The token is stored in AWS Secrets
Manager at `platform/cloudflare/api-token` and read via a data source
at plan/apply time.

### Procedure

1. **Generate a new token** in the
   [Cloudflare dashboard](https://dash.cloudflare.com/profile/api-tokens).
   The token needs `Zone:DNS:Edit` and `Zone:Zone:Read` permissions for
   the relevant zones.

2. **Revoke the old token** in the dashboard after the new token is
   verified (step 4).

3. **Update the secret in Secrets Manager:**

   ```bash
   aws secretsmanager put-secret-value \
     --secret-id platform/cloudflare/api-token \
     --secret-string '<new-token>' \
     --region us-east-1 \
     --profile platform
   ```

4. **Verify** the new token works:

   ```bash
   cd infra/live/aws/platform/us-east-1/platform/cloudflare-dns
   terragrunt plan
   ```

   Plan should succeed with no authentication errors. Expect no changes
   unless DNS records were modified.

---

## 2. Tailscale API Key Rotation

The Tailscale API key authenticates the Tailscale Terraform provider used
by both `tailscale-admin` and `tailscale` units. Keys expire after **90
days** by default.

### Procedure

1. **Generate a new API key** in
   [Tailscale admin](https://login.tailscale.com/admin/settings/keys) >
   Settings > Keys.

2. **Update the secret in Secrets Manager:**

   ```bash
   aws secretsmanager put-secret-value \
     --secret-id platform/tailscale/api-key \
     --secret-string '<NEW_KEY>' \
     --region us-east-1 \
     --profile platform
   ```

3. **Verify** both units that consume this key:

   ```bash
   cd infra/live/aws/platform/us-east-1/platform/tailscale-admin
   terragrunt plan
   ```

   ```bash
   cd infra/live/aws/platform/us-east-1/platform/tailscale
   terragrunt plan
   ```

   Both plans should succeed with no authentication errors.

4. **Revoke the old key** in the Tailscale admin console after
   verification.

**Important:** Both `tailscale-admin` and `tailscale` units read from the
same `platform/tailscale/api-key` secret. A single update covers both.

---

## 3. Tailscale OAuth Client Rotation

The OAuth client credentials authenticate the Tailscale Kubernetes
Operator. These credentials are Terraform-managed by the `tailscale-admin`
module -- they are created as a `tailscale_oauth_client` resource and
stored in Secrets Manager at `platform/tailscale/oauth`.

Rotate only if the credentials are compromised. Routine rotation is not
required.

### Procedure

1. **Rotate the OAuth client** by re-applying `tailscale-admin`:

   ```bash
   cd infra/live/aws/platform/us-east-1/platform/tailscale-admin
   terragrunt apply
   ```

   This creates a new OAuth client and updates the Secrets Manager secret
   with the new `clientId` and `clientSecret`.

2. **Propagate the new credentials** to the K8s operator:

   ```bash
   cd infra/live/aws/platform/us-east-1/platform/tailscale
   terragrunt apply
   ```

   The operator pod will restart with the new credentials.

3. **Verify** the operator reconnects:

   ```bash
   kubectl get pods -n tailscale-system
   kubectl logs -n tailscale-system -l app=tailscale -c tailscale --tail=20
   ```

   Look for a successful connection to `controlplane.tailscale.com`.

**Note:** There will be a brief period of operator downtime while the K8s
operator pod restarts and reconnects with the new credentials. Existing
Tailscale connections are not interrupted -- only the operator's ability
to manage devices is temporarily affected.

---

## 4. ArgoCD SSO CA Certificate Renewal

The SAML signing certificate from AWS Identity Center validates SSO login
responses. When Identity Center rotates the certificate, ArgoCD must be
updated or SSO login will fail with a certificate verification error.

### Procedure

1. **Export the new certificate** from the Identity Center SAML
   application:

   - Open the [IAM Identity Center console](https://console.aws.amazon.com/singlesignon)
     in the management account (851725353202)
   - Navigate to **Applications** > **ArgoCD** > application details
   - Download the **SAML metadata XML**

2. **Extract and encode the certificate** from the metadata XML:

   ```bash
   xmllint --xpath '//*[local-name()="X509Certificate"]/text()' metadata.xml \
     | fold -w 64 \
     | { echo "-----BEGIN CERTIFICATE-----"; cat; echo "-----END CERTIFICATE-----"; } \
     > signing-cert.pem

   base64 -i signing-cert.pem | tr -d '\n'
   ```

   > **Warning:** Do NOT use the certificate downloaded from the Identity
   > Center console ("Download certificate" button). Always extract the
   > certificate from the SAML metadata XML -- it contains the exact
   > certificate used to sign SAML responses.

3. **Update** `argocd_sso_ca_data` in `infra/live/aws/common.hcl` with
   the base64-encoded certificate from step 2.

4. **Apply:**

   ```bash
   cd infra/live/aws/platform/us-east-1/platform/argocd
   terragrunt apply
   ```

   The `configHash` annotation in the Helm release triggers an automatic
   pod restart.

5. **Verify** SSO login:
   - Access the ArgoCD UI at `https://argocd.aws.refplat.org`
   - Click "Log in via SSO"
   - Complete authentication through Identity Center
   - Confirm group-based RBAC permissions are working (admin users can
     see all applications, developers can sync)

**Break-glass:** If SSO is completely broken, use the local admin account:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

Log in with username `admin` and the retrieved password.

---

## 5. Emergency: Compromised Secret Response

If a secret is known or suspected to be compromised, follow this
procedure immediately. Do not wait for the normal rotation schedule.

### Step 1: Immediately Rotate the Compromised Secret

Use the relevant section above to rotate the secret:

| Secret | Section |
|--------|---------|
| Cloudflare API token | [Section 1](#1-cloudflare-api-token-rotation) |
| Tailscale API key | [Section 2](#2-tailscale-api-key-rotation) |
| Tailscale OAuth client | [Section 3](#3-tailscale-oauth-client-rotation) |
| ArgoCD SSO CA cert | [Section 4](#4-argocd-sso-ca-certificate-renewal) |

**Revoke the old credential immediately** -- do not wait for verification
of the new credential.

### Step 2: Assess Blast Radius

Query CloudTrail for any usage of the compromised credential:

```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=ResourceName,AttributeValue=platform/tailscale/api-key \
  --start-time "$(date -u -v-7d '+%Y-%m-%dT%H:%M:%SZ')" \
  --region us-east-1 \
  --profile platform \
  --query 'Events[].{Time:EventTime,Name:EventName,User:Username}' \
  --output table
```

Replace the `AttributeValue` with the relevant resource name. Adjust
`--start-time` to cover the window of exposure.

For Secrets Manager access specifically:

```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=GetSecretValue \
  --start-time "$(date -u -v-7d '+%Y-%m-%dT%H:%M:%SZ')" \
  --region us-east-1 \
  --profile platform \
  --query 'Events[].{Time:EventTime,User:Username,Resource:Resources[0].ResourceName}' \
  --output table
```

### Step 3: Check for Lateral Movement

Determine if the compromised credential was used to access other systems:

- **Tailscale API key:** Check if unauthorized devices were added to the
  tailnet (Tailscale admin > Machines).
- **Tailscale OAuth client:** Check if unauthorized auth keys were
  created (Tailscale admin > Settings > Keys).
- **Cloudflare API token:** Check DNS records for unauthorized
  modifications (`cloudflare-dns` unit, Cloudflare dashboard audit log).
- **ArgoCD SSO cert:** Check ArgoCD audit logs for unauthorized logins:

  ```bash
  kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server \
    --since=168h | grep "authentication"
  ```

### Step 4: Data Breach Assessment

If the compromised credential could have provided access to customer data
or PII, follow the data breach notification procedures:

- Notify the Security team immediately: Slack `#security`
- Document what data could have been accessed
- Preserve all audit logs (do not delete CloudTrail events)
- Engage legal if required by compliance framework

### Step 5: Add Monitoring

Add a CloudWatch alarm for the suspicious access pattern to detect
future compromise:

```bash
# Example: alarm on unexpected GetSecretValue calls
aws cloudwatch put-metric-alarm \
  --alarm-name "unexpected-secret-access-platform-tailscale" \
  --metric-name "SecretAccess" \
  --namespace "CustomMetrics/SecretsManager" \
  --statistic Sum \
  --period 300 \
  --threshold 10 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 1 \
  --alarm-actions "<sns-topic-arn>" \
  --region us-east-1 \
  --profile platform
```

### Step 6: Post-Incident Review

Within 48 hours of the incident:

1. Document the root cause (how was the secret exposed?)
2. Document the timeline (when was it compromised, when was it detected,
   when was it rotated?)
3. Identify prevention measures (secrets scanning in CI, restricted
   access policies, shorter expiry windows)
4. File action items with owners and due dates
5. Update this runbook if the incident revealed gaps in the procedure

---

## 6. Proactive: Tracking Secret Expiry

### Secret Inventory

| Secret | Location | Expiry | Rotation Trigger |
|--------|----------|--------|------------------|
| Tailscale API key | `platform/tailscale/api-key` (Secrets Manager) | 90 days | Calendar reminder |
| Tailscale OAuth client | `platform/tailscale/oauth` (Secrets Manager) | No expiry | Compromise only |
| Cloudflare API token | `platform/cloudflare/api-token` (Secrets Manager) | No expiry | Compromise or policy |
| ArgoCD SSO CA cert | `argocd_sso_ca_data` in `common.hcl` | Varies (IdC rotation) | Identity Center notification |

### Checking Current Key Age

**Tailscale API key:**

```bash
aws secretsmanager describe-secret \
  --secret-id platform/tailscale/api-key \
  --region us-east-1 \
  --profile platform \
  --query '{LastChanged:LastChangedDate,NextRotation:NextRotationDate}' \
  --output table
```

**Tailscale OAuth client:**

```bash
aws secretsmanager describe-secret \
  --secret-id platform/tailscale/oauth \
  --region us-east-1 \
  --profile platform \
  --query '{LastChanged:LastChangedDate}' \
  --output table
```

### Rotation Schedule

Set a calendar reminder for **80 days** after the last Tailscale API key
rotation (10 days before the 90-day expiry). To calculate the next
rotation date:

```bash
LAST_CHANGED=$(aws secretsmanager describe-secret \
  --secret-id platform/tailscale/api-key \
  --region us-east-1 \
  --profile platform \
  --query 'LastChangedDate' --output text)

echo "Last rotated: $LAST_CHANGED"
echo "Rotate by:    $(date -j -v+80d -f '%Y-%m-%dT%H:%M:%S' \
  "$(echo $LAST_CHANGED | cut -d. -f1)" '+%Y-%m-%d')"
```

### Future: Automated Expiry Notifications

Automate rotation reminders with CloudWatch Events and SNS:

```bash
# Create SNS topic for rotation alerts
aws sns create-topic \
  --name secret-rotation-alerts \
  --region us-east-1 \
  --profile platform

# Subscribe the platform team
aws sns subscribe \
  --topic-arn arn:aws:sns:us-east-1:829808296602:secret-rotation-alerts \
  --protocol email \
  --notification-endpoint platform-team@company.com \
  --region us-east-1 \
  --profile platform
```

A Lambda function or EventBridge rule can check `LastChangedDate` daily
and publish to the SNS topic when a secret is within 10 days of expiry.
This is not yet implemented.
