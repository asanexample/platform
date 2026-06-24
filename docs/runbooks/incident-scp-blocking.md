# Runbook: Incident Response -- SCP Blocking Legitimate Actions

> **Severity:** High (can block deployments and production operations)
> **On-call scope:** Infrastructure / Platform Engineering
> **Module path:** `infra/modules/aws/organizations/scps.tf`
>
> **Last reviewed:** 2026-06-01

---

## Table of Contents

1. [Symptoms](#symptoms)
2. [Step 1: Identify the Blocking SCP](#step-1-identify-the-blocking-scp)
3. [Step 2: Assess Impact and Decide on Response](#step-2-assess-impact-and-decide-on-response)
4. [Step 3a: Add a Temporary Exempt Role](#step-3a-add-a-temporary-exempt-role)
5. [Step 3b: Emergency SCP Detachment](#step-3b-emergency-scp-detachment)
6. [Step 4: Resolve the Root Cause](#step-4-resolve-the-root-cause)
7. [Step 5: Post-Incident Actions](#step-5-post-incident-actions)
8. [Escalation Path](#escalation-path)
9. [Reference: SCP-to-Error Mapping](#reference-scp-to-error-mapping)

---

## Symptoms

An SCP blocking a legitimate action typically manifests as:

- `AccessDeniedException` or `AccessDenied` errors in application logs, CI/CD pipelines,
  or CLI output -- even when the IAM role/policy grants the required permissions.
- The error message may or may not reference `organizations` or SCP. AWS does not always
  include SCP details in the error response.
- The same action works in one account but not another (different OU = different SCPs).
- The action worked previously but stopped after an SCP change or account OU move.

**Key distinction:** SCP denials override IAM Allow policies. If IAM permissions look
correct, suspect an SCP.

---

## Step 1: Identify the Blocking SCP

### Option A: CloudTrail Event History (Fastest)

1. Open CloudTrail in the affected account and region.
2. Filter by:
   - **Event name:** The API action that was denied (e.g., `RunInstances`).
   - **User name / Role:** The identity that received the denial.
   - **Time range:** Narrow to when the error occurred.

3. Inspect the event. Look for:

   ```json
   {
     "errorCode": "Client.UnauthorizedOperation",
     "errorMessage": "You are not authorized to perform this operation. Encoded authorization failure message: ..."
   }
   ```

4. Decode the authorization failure message:

   ```bash
   aws sts decode-authorization-message \
     --encoded-message "<encoded-message>" \
     --query 'DecodedMessage' --output text | jq .
   ```

   The decoded message includes `explicitDeny: true` and may reference the SCP that
   caused the denial.

### Option B: CloudTrail Lake (Comprehensive)

```sql
SELECT eventTime, eventName, eventSource, userIdentity.arn,
       errorCode, errorMessage, requestParameters
FROM <event-data-store-id>
WHERE errorCode IN ('AccessDenied', 'Client.UnauthorizedOperation')
  AND recipientAccountId = '<affected-account-id>'
  AND eventTime > '<incident-start-time>'
ORDER BY eventTime DESC
LIMIT 50;
```

### Option C: IAM Access Analyzer Policy Simulation

Use the Access Analyzer to simulate the action and identify which policy layer denied it:

```bash
aws iam simulate-custom-policy \
  --policy-input-list "$(aws iam get-role-policy --role-name <role> --policy-name <policy> \
    --query 'PolicyDocument' --output json)" \
  --action-names "<denied-action>" \
  --resource-arns "<resource-arn>"
```

Note: This simulates IAM policies only, not SCPs. If the simulation returns `allowed`
but the real call is denied, an SCP is the likely cause.

### Option D: Manual SCP Review

List all SCPs effective on the account and search for the denied action:

```bash
# Get the account's parent OU
ACCOUNT_ID="<affected-account-id>"
PARENT_ID=$(aws organizations list-parents --child-id "$ACCOUNT_ID" \
  --query 'Parents[0].Id' --output text)

# List SCPs on the account directly, its OU, and the root
for target in "$ACCOUNT_ID" "$PARENT_ID" "<root-id>"; do
  echo "=== Target: $target ==="
  aws organizations list-policies-for-target \
    --target-id "$target" \
    --filter SERVICE_CONTROL_POLICY \
    --query 'Policies[].{Name:Name,Id:Id}'
done

# For each SCP, check if it denies the action
POLICY_ID="<suspect-scp-id>"
aws organizations describe-policy --policy-id "$POLICY_ID" \
  --query 'Policy.Content' --output text | jq .
```

Search the policy JSON for the denied action name. Check both `Action` and `NotAction`
blocks. Remember that `NotAction` in a Deny statement means "deny everything except
what is listed."

---

## Step 2: Assess Impact and Decide on Response

| Scenario | Recommended Response | Time to Resolve |
|---|---|---|
| Non-production account, non-urgent | Update SCP via normal PR process | Hours to days |
| Production deployment blocked | Add temporary exempt role (Step 3a) | 15-30 minutes |
| Active incident, production down | Emergency SCP detachment (Step 3b) | 5-10 minutes |
| SCP is working correctly, action should be denied | Fix the caller (no SCP change needed) | Varies |

**Decision tree:**

1. Is the action legitimately needed? If no, fix the application/pipeline -- the SCP
   is doing its job.
2. Is this urgent (production impact)? If yes, proceed to Step 3a or 3b.
3. Can you wait for a normal PR cycle? If yes, skip to Step 4.

---

## Step 3a: Add a Temporary Exempt Role

This is the **safest emergency response**. It adds a single role to the SCP exemption
list without modifying the SCP logic.

### Prerequisites

- Access to the management account with permissions to update the organizations module.
- The role that needs exemption must already exist in the target account.

### Procedure

1. **Edit `terragrunt.hcl`** to add the role to `exempt_roles`:

   ```hcl
   inputs = {
     exempt_roles = [
       # Keep ALL six live entries — do NOT drop these:
       "OrganizationAccountAccessRole",
       "github-actions-terratest",
       "PlatformDeployer",
       "crossplane-ecr-provisioner",     # environment ECR provisioning
       "crossplane-provisioner-*",       # environment IAM/EKS provisioning
       "*-karpenter-*",                  # Karpenter node provisioning (ADR-078)
       "TemporaryExempt-INCIDENT-1234",  # <-- add with incident ticket reference
     ]
   }
   ```

2. **Plan and apply:**

   ```bash
   cd infra/live/aws/mgmt/global/organizations
   terragrunt plan    # Review: should show SCP content updates only
   terragrunt apply
   ```

3. **Verify the blocked action now succeeds** when performed by the exempt role.

4. **Set a calendar reminder** to remove the temporary exemption within 24-48 hours
   after the root cause is resolved.

### Cleanup

After the incident is resolved, remove the temporary role from `exempt_roles` and
reapply. Document the removal in the incident ticket.

---

## Step 3b: Emergency SCP Detachment

**Use only when production is actively impacted and Step 3a is insufficient or too slow.**

This procedure detaches an SCP from its target, which disables the SCP's deny
statements for all accounts under that target. This is a broad change with compliance
implications.

### Prerequisites

- Management account access with `organizations:DetachPolicy` permission.
- Knowledge of which SCP to detach (from Step 1).

### Procedure

1. **Identify the SCP ID and target ID:**

   ```bash
   # Find the SCP
   aws organizations list-policies --filter SERVICE_CONTROL_POLICY \
     --query 'Policies[].{Name:Name,Id:Id}'

   # Find where it is attached
   SCP_ID="p-xxxxxxxxxx"
   aws organizations list-targets-for-policy --policy-id "$SCP_ID" \
     --query 'Targets[].{Name:Name,Id:TargetId,Type:Type}'
   ```

2. **Detach the SCP:**

   ```bash
   aws organizations detach-policy \
     --policy-id "$SCP_ID" \
     --target-id "<target-id>"
   ```

   This takes effect within seconds. No Terraform apply is needed for emergency
   detachment.

3. **Verify the blocked action now succeeds.**

4. **Immediately notify the Security team** that an SCP has been detached. Provide:
   - Which SCP was detached.
   - Which target it was detached from.
   - Why (incident ticket number).
   - Expected duration.

### Re-attachment

After the root cause is resolved, re-attach the SCP:

```bash
aws organizations attach-policy \
  --policy-id "$SCP_ID" \
  --target-id "<target-id>"
```

Then **reconcile Terraform state** to avoid drift:

```bash
cd infra/live/aws/mgmt/global/organizations
terragrunt plan
# If plan shows re-creation of the attachment, apply it:
terragrunt apply
```

If you modified the SCP content (not just attachment), import or reconcile accordingly.

---

## Step 4: Resolve the Root Cause

After the immediate impact is mitigated, determine the permanent fix:

### The action should be allowed

- **Option A: Modify the SCP** to add a condition that allows the specific use case.
  For example, adding a condition that allows the action for a specific role or service:

  ```hcl
  condition {
    test     = "ArnNotLike"
    variable = "aws:PrincipalArn"
    values   = concat(local.exempt_role_arns, [
      "arn:aws:iam::*:role/CICDDeployRole"
    ])
  }
  ```

- **Option B: Move the account** to a different OU with a more permissive SCP set.

- **Option C: Remove the specific statement** if the control is no longer needed.

Follow the process in `docs/runbooks/modify-scps.md` for making permanent SCP changes.

### The action should be denied (SCP is correct)

- Fix the application, pipeline, or human process that is attempting the denied action.
- Update the IAM role to not attempt the denied action.
- If the action is needed but in a different way (e.g., encrypted instead of unencrypted),
  update the resource configuration to comply with the SCP condition.

---

## Step 5: Post-Incident Actions

1. **Write an incident report** including:
   - Timeline of events.
   - Root cause (SCP misconfiguration, missing exemption, new workload requirement, etc.).
   - Impact (which services/teams were affected, duration).
   - Permanent fix applied.
   - Action items to prevent recurrence.

2. **Update documentation:**
   - If the SCP was modified, update `docs/compliance/scp-control-mapping.md`.
   - If a new exempt role was added permanently, document the justification.
   - If a new type of denial was encountered, add it to the
     [Reference table](#reference-scp-to-error-mapping) below.

3. **Verify compliance posture:**
   - Confirm all SCPs are re-attached.
   - Run a compliance scan (Security Hub, AWS Config) to ensure no drift.
   - Verify Terraform state matches actual state: `terragrunt plan` should show
     no changes.

4. **Remove temporary exemptions:**
   - If a temporary exempt role was added, remove it and reapply.
   - If an SCP was detached, confirm it is re-attached.

---

## Escalation Path

| Time Elapsed | Action | Contact |
|---|---|---|
| 0 minutes | On-call engineer begins investigation | On-call pager |
| 15 minutes | If production impact, begin Step 3a or 3b | On-call engineer |
| 30 minutes | If not resolved, escalate to platform engineering lead | Slack: #platform-engineering |
| 1 hour | If SCP detachment was required, notify Security team | Slack: #security, security@company.com |
| 2 hours | If still unresolved, escalate to VP Engineering | Direct page |
| 4 hours | If AWS-side issue suspected, open AWS Support case (Severity 1 for production down) | AWS Support Console |

**AWS Support note:** For SCP-related issues, file under "Account and Billing" >
"Organizations" or "Security, Identity, and Compliance" > "IAM". Include the CloudTrail
event ID and the decoded authorization failure message.

---

## Reference: SCP-to-Error Mapping

Use this table to quickly identify which SCP is likely responsible for a specific error:

| Error / Denied Action | Likely SCP | Statement SID | Resolution |
|---|---|---|---|
| `LeaveOrganization` denied | baseline-guardrails | DenyLeaveOrganization | This is always intentional. No fix needed. |
| Root user action denied | baseline-guardrails | DenyRootUserActions | Use a named IAM role instead of root. |
| `CreateAccessKey` denied on root | baseline-guardrails | DenyRootAccessKeys | Use SSO or role-based temporary credentials. |
| `EnableRegion` / `DisableRegion` denied | baseline-guardrails | DenyRegionChanges | Use an exempt role or request region change via management account. |
| Password policy change denied | baseline-guardrails | DenyPasswordPolicyChanges | Use an exempt role. |
| `OrganizationAccountAccessRole` modification denied | baseline-guardrails | ProtectOrganizationRole | Use an exempt role from the management account. |
| CloudTrail `StopLogging` / `DeleteTrail` denied | protect-security-services | ProtectCloudTrail | Do not disable CloudTrail. |
| Config recorder actions denied | protect-security-services | ProtectConfig | Do not disable AWS Config. |
| GuardDuty actions denied | protect-security-services | ProtectGuardDuty | Do not disable GuardDuty. |
| Security Hub disable denied | protect-security-services | ProtectSecurityHub | Do not disable Security Hub. |
| `DeleteFlowLogs` denied | protect-security-services | ProtectFlowLogs | Do not delete VPC Flow Logs. |
| `CreateVolume` denied (EBS) | enforce-encryption | DenyUnencryptedVolumes | Add `encrypted = true` to the volume configuration. |
| `RunInstances` denied (unencrypted block device) | enforce-encryption | DenyUnencryptedEbsOnLaunch | Encrypt all block devices in the launch template / instance config. |
| `PutObject` denied (S3) | enforce-encryption | DenyUnencryptedS3Uploads | Send the `x-amz-server-side-encryption` header (`aws:kms` or `AES256`). |
| `CreateDBInstance` denied (RDS) | enforce-encryption | DenyUnencryptedRds | Add `storage_encrypted = true` to the RDS configuration. |
| `RunInstances` denied (EC2) | enforce-encryption | EnforceIMDSv2 | Set `http_tokens = "required"` in the instance metadata options. |
| Action denied in non-allowed region | deny-regions | DenyNonAllowedRegions | Use `us-east-1` or `us-west-2`. If a new region is needed, update `allowed_regions`. |
| `PutAccountPublicAccessBlock` denied | protect-data-and-network | ProtectS3PublicAccessBlock | Do not weaken S3 public access blocks. |
| `CreateDefaultVpc` denied | protect-data-and-network | DenyDefaultVpc | Use custom VPCs, not default VPCs. |
| `CreateResourceShare` denied (RAM) | protect-data-and-network | DenyExternalSharing | Set `allow_external_principals = false` on the RAM share. |
| Backup/Glacier deletion denied | protect-data-and-network | ProtectBackups | Do not delete backups. Use an exempt role if decommissioning. |
| `TagResource`/`UntagResource` denied on `Team` tag | protect-data-and-network | DenyTeamTagTampering | The `Team` tag is set by IaC/platform roles only; don't relabel resources by hand (ABAC integrity). |
| Resource creation denied (missing tags) | require-tagging | RequireTag* | Add the required tags: `Environment`, `ManagedBy`, `Owner`. |
| `CreateUser` / `CreateAccessKey` denied | restrict-iam-users | DenyIamUserCreation | Use IAM roles and SSO, not IAM users. |
| `AttachUserPolicy` denied | restrict-iam-users | DenyUserPolicyAttachment | Attach policies to roles, not users. |
| Non-HIPAA service action denied | hipaa-eligible-services | DenyNonHipaaServices | Use only HIPAA-eligible services. Check the AWS HIPAA Eligible Services list. |
