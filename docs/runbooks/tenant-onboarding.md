# Runbook: Tenant Team Onboarding (Preprod EKS)

> **On-call scope:** Platform Engineering
> **Model:** Tenants are provisioned by the Crossplane **Tenant control plane** via an `XTenant` claim (BACK
> stack P3, [ADR-046](../adrs/046-back-stack-for-developer-self-service.md) /
> [ADR-048](../adrs/048-federated-per-cluster-crossplane.md)). A single claim provisions the complete tenant.
> The old Terragrunt path (`tenants`/`pod-identity`/`s3-shared` units, the `tenant` module) is **retired**.
> **Live configurations:**
>
> - `gitops/tenant-claims/preprod/<team>.yaml` — **the claim** (one `XTenant`, synced by ArgoCD — primary)
> - `infra/live/aws/preprod/us-east-1/platform/teams.hcl` — app-delivery + supply-chain inputs only
> - `infra/live/aws/mgmt/global/identity-center/terragrunt.hcl` — the team's `Dev-<team>` SSO permission set
> - `infra/live/aws/platform/us-east-1/platform/argocd-apps/terragrunt.hcl` — app delivery (ArgoCD)
> - `infra/live/aws/platform/us-east-1/platform/github-oidc/terragrunt.hcl` — app CI OIDC (signing)
>
> **Last reviewed:** 2026-06-03

See [Crossplane Tenant API](../architecture/crossplane-tenant-api.md) for the XRD schema, what the
Composition provisions, and the claim lifecycle.

---

## Table of Contents

1. [What a claim provisions](#what-a-claim-provisions)
2. [Prerequisites](#prerequisites)
3. [Onboarding a new team](#onboarding-a-new-team)
4. [Verification](#verification)
5. [Offboarding](#offboarding)
6. [Migrating a team off the legacy `teams.hcl` path](#migrating-a-team-off-the-legacy-teamshcl-path)
7. [Troubleshooting](#troubleshooting)

---

## What a claim provisions

One `XTenant` claim → the Composition reconciles the **complete** tenant:

- **Kubernetes:** namespace `team-<team>`, ResourceQuota, LimitRange, default-deny + allow NetworkPolicies,
  CiliumNetworkPolicies, the `team-<team>:developers` RoleBinding, and the per-team Kyverno
  `restrict-images` + `restrict-route-hostnames` policies.
- **AWS (preprod):** `Pod-team-<team>` IAM role (deny-escalation boundary) + EKS Pod Identity association;
  `DeveloperAccess-<team>` IAM role + EKS access entry → the `team-<team>:developers` group.
- **AWS (platform account, cross-account):** the `team-<team>/<app>` ECR repo + pull policy, per app.

**Not** provisioned by the claim (still platform-owned / separate): the cosign/SLSA
`verify-images`/`verify-attestations` policies (the `policy` unit), the `Dev-<team>` SSO permission set
(`identity-center`), and app delivery (the ArgoCD Application, `argocd-apps`).

---

## Prerequisites

- [ ] Active AWS SSO session for the **management** profile (`aws sso login --profile management`).
- [ ] Your SSO identity can assume **PlatformDeployer** in the preprod and platform accounts.
- [ ] `terragrunt` + `kubectl` configured; preprod reachable (Tailscale for kubectl).
- [ ] If the team's developers need cluster/AWS access, plan to add their **AWS Identity Center** wiring —
      the `Dev-<team>` permission set + `Developers-<team>` group + assignment + users. This is partly
      manual (per-user invite/MFA, or external-IdP group management); see
      [Step 4](#step-4--grant-developer-access-aws-identity-center). The claim's `DeveloperAccess-<team>`
      role trusts the `Dev-<team>` SSO principal, so the role can exist before this — but no human can use it
      until Identity Center is wired up.
- [ ] The crossplane control plane is healthy: `kubectl --context preprod get providers.pkg.crossplane.io`
      (all Healthy) and `kubectl --context preprod get xrd xtenants.platform.refplat.org` (Established).

---

## Onboarding a new team

### Step 1 — Author the `XTenant` claim

Create `gitops/tenant-claims/preprod/<team>.yaml` (a single `XTenant`) via PR. The file **is** the claim:

```yaml
apiVersion: platform.refplat.org/v1alpha1
kind: XTenant
metadata:
  name: charlie
spec:
  team: charlie
  hostnames:
    - charlie.preprod.aws.refplat.org # must be in the team's allow-list (drives restrict-route-hostnames)
  apps:
    api:
      repoPath: k8s/preprod
      preview: true # → ECR repo team-charlie/api
  aws:
    serviceAccount: app-charlie # the named SA the app's pods run as
    # Generic IAM granted to Pod-team-charlie (capped by the deny-escalation boundary). Empty = no AWS perms.
    # NOTE: S3 buckets are NOT created (that was a demo) — grant access to existing resources here.
    policyStatements: []
  # resourceQuota omitted → XRD defaults (cpu 4, memory 8Gi, pods 20, …)
  # developerAccess omitted → enabled by default
```

### Step 2 — Register the team for app delivery + supply chain (`teams.hcl`)

The claim owns infra; `teams.hcl` still drives **app delivery** (ArgoCD) and the **supply-chain policies**.
Add the team with `migrated = true` so it is excluded from the (retired) Terragrunt infra loops and the
`policy` unit skips its `restrict-*` (the Composition owns those):

```hcl
charlie = {
  mode      = "namespace"
  migrated  = true
  hostnames = ["charlie.preprod.aws.refplat.org"]
  apps = {
    api = {
      repo_url  = "https://github.com/asanexample/app-charlie"
      repo_path = "k8s/preprod"
      preview   = true
    }
  }
}
```

### Step 3 — Apply

Open a PR with the claim YAML (`gitops/tenant-claims/preprod/charlie.yaml`) — the path is CODEOWNERS-gated.
On merge, the `tenant-claims-preprod` ArgoCD Application syncs it to the preprod cluster (`selfHeal` +
`prune` + ServerSideApply) and the Composition reconciles it (~1–2 min). **No Terragrunt, no
`terragrunt apply`** for the claim itself.

The units that read `teams.hcl` for delivery + supply chain are still Terragrunt — apply them as before:

```bash
cd infra/live/aws/preprod/us-east-1/platform/policy && AWS_PROFILE=management terragrunt apply   # per-team verify-* policies
cd ../../../../platform/us-east-1/platform/argocd-apps && AWS_PROFILE=management terragrunt apply  # ArgoCD app
```

### Step 4 — Grant developer access (AWS Identity Center)

The claim provisions the `DeveloperAccess-<team>` IAM role + the EKS access entry, but **a human reaches it
through AWS Identity Center**: they sign in to the AWS access portal, select the `Dev-<team>` permission set
on the preprod account (account-wide read + permission to assume `DeveloperAccess-<team>`), and from there
get namespace-scoped kubectl. This wiring is **hand-maintained** in the `identity-center` unit (mgmt
account) and has a few genuinely manual, console-only steps. Skip this step for a team with no human
developers yet (e.g. a workload-only team).

#### 4a. Add the team to the `identity-center` unit (HCL)

Edit `infra/live/aws/mgmt/global/identity-center/terragrunt.hcl` — add three things, mirroring the existing
`alpha`/`bravo` entries:

```hcl
# 1) permission_sets — a Dev-<team> set: account-wide read + assume only this team's DeveloperAccess role
"Dev-charlie" = {
  description      = "Developer access for team charlie (preprod)"
  session_duration = "PT4H"
  managed_policies = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
  inline_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AssumeTeamDeveloperRole"
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = "arn:aws:iam::${dependency.organizations.outputs.account_ids["Preprod"]}:role/DeveloperAccess-charlie"
      },
      {
        # Per-team ABAC (#62): deny acting on another team's tagged resources
        Sid      = "DenyOtherTeamsResources"
        Effect   = "Deny"
        Action   = "*"
        Resource = "*"
        Condition = {
          StringNotEquals = { "aws:ResourceTag/Team" = ["charlie", "platform"] }
          Null            = { "aws:ResourceTag/Team" = "false" }
        }
      },
    ]
  })
}

# 2) groups — the team's developer group
"Developers-charlie" = { description = "Developers for team charlie" }

# 3) account_assignments — bind the set to the group on Preprod (append to the list)
{ account_id = dependency.organizations.outputs.account_ids["Preprod"], permission_set = "Dev-charlie", group = "Developers-charlie" },
```

Then add the developers (see 4b for which path applies):

```hcl
# users — only when AWS Identity Center is the identity source (NOT when syncing from an external IdP)
"charlie-dev" = {
  given_name  = "Charlie"
  family_name = "Developer"
  email       = "charlie-dev@example.com" # the person's real email
  groups      = ["Developers-charlie"]
}
```

Apply from the management account:

```bash
cd infra/live/aws/mgmt/global/identity-center
AWS_PROFILE=management terragrunt apply
```

This creates the permission set, group, group memberships, and the account assignment via the AWS APIs — no
console clicks for those.

#### 4b. Provision the actual people — the manual part

Which path applies depends on your **identity source** (IAM Identity Center → Settings → Identity source):

- **AWS Identity Center is the identity source** (this repo's default — `users` are managed in HCL as in 4a).
  Terraform creates each user, but AWS then requires **per-user, manual, browser steps**:
  1. The user receives an **"Invitation to join IAM Identity Center"** email. (If it didn't arrive, an admin
     can resend: IAM Identity Center console → **Users** → select the user → **Send email verification
     link / Reset password**.)
  2. The user clicks **Accept invitation**, sets a password, and **registers an MFA device** (required —
     Identity Center enforces MFA by default). This cannot be done by Terraform.
  3. (Optional) An admin can verify membership: console → **Groups** → `Developers-charlie` → confirm the
     user is listed.

- **External IdP via SCIM** (Okta / Entra ID / etc.). Do **not** put `users` in the HCL. Instead:
  1. In the IdP, create/assign the user to a group that SCIM-provisions into Identity Center as
     `Developers-charlie` (the group name must match the HCL `groups` + `account_assignments` entry).
  2. Confirm the synced group appears: IAM Identity Center console → **Groups**.
  3. The permission set + assignment from 4a still come from HCL; only users/groups live in the IdP.

> One-time, **not per team:** ArgoCD SSO uses a SAML app created by hand in the Identity Center console (see
> [onboarding.md](../onboarding.md)). New teams get ArgoCD access through their group → ArgoCD RBAC, so you
> do **not** create a new SAML app per team.

#### 4c. How the developer then gets access (hand this to them)

```bash
# One-time: configure an SSO profile (uses the AWS access portal / start URL)
aws configure sso            # SSO start URL = the org's access-portal URL; region us-east-1
# pick the Preprod account + the "Dev-charlie" role when prompted; name the profile e.g. charlie-dev

# kubectl, scoped to their namespace (the DeveloperAccess-charlie role → team-charlie:developers RBAC)
aws eks update-kubeconfig --name preprod-use1-eks --region us-east-1 \
  --role-arn arn:aws:iam::<preprod-account>:role/DeveloperAccess-charlie --profile charlie-dev
kubectl get pods -n team-charlie    # works; other namespaces are denied
```

The `Dev-charlie` permission set itself only grants account-wide **read** + `sts:AssumeRole` into
`DeveloperAccess-charlie`; all cluster authority is the namespace-scoped RBAC the claim bound to
`team-charlie:developers` (ADR-039/040).

---

## Verification

```bash
# The claim + its managed resources
kubectl --context preprod get xtenant charlie                 # SYNCED=True READY=True
kubectl --context preprod get managed | grep charlie          # all Object + aws.upbound.io MRs Ready

# Kubernetes side
kubectl --context preprod get ns team-charlie
kubectl --context preprod get resourcequota,rolebinding -n team-charlie
kubectl --context preprod get clusterpolicy | grep charlie    # restrict-* (claim) + verify-* (policy unit) = 4

# AWS side
aws iam get-role --role-name Pod-team-charlie --profile preprod                          # boundary + Team tag
aws eks describe-access-entry --cluster-name preprod-use1-eks \
  --principal-arn arn:aws:iam::<preprod>:role/DeveloperAccess-charlie --profile preprod   # → team-charlie:developers
aws ecr describe-repositories --repository-names team-charlie/api --profile platform      # cross-account repo
```

A compliant workload referencing `…/team-charlie/api:<tag>` should admit; a cross-team image is denied by
`restrict-images-team-charlie`.

---

## Offboarding

1. Remove the team's `gitops/tenant-claims/preprod/<team>.yaml` via PR — on merge, the `tenant-claims-preprod`
   ArgoCD Application prunes the `XTenant` and the Composition cascades the teardown of **every** managed
   resource (the namespace + AWS, both accounts) via finalizers.
2. Remove the team from `teams.hcl` and apply `policy` + `argocd-apps` (drops its verify-* policies + ArgoCD
   app).
3. If the team is fully gone, remove its Identity Center wiring from the `identity-center` unit (the
   `Dev-<team>` permission set, `Developers-<team>` group, its `users`, and the `account_assignments` entry)
   and `terragrunt apply` from the mgmt account. With an external IdP, also remove the group/members there.
   (Terraform deletes the SSO objects; no separate console step is needed to *deprovision*, unlike the
   manual *activation* on onboarding.)
4. Verify: `kubectl get xtenant <team>` (NotFound), `aws iam get-role --role-name Pod-team-<team>`
   (NoSuchEntity), the ECR repo is gone in the platform account.

---

## Migrating a team off the legacy `teams.hcl` path

Only relevant for a team that predates the claim model (alpha + bravo are already migrated). The mechanics
are the same as a normal cutover; the one wrinkle is **state already exists**:

1. Author the `XTenant` (Step 1) and set `migrated = true` (Step 2).
2. **ECR:** if the team's `team-<team>/<app>` repo holds live images, `terragrunt state rm` it from the `ecr`
   unit **before** applying (so the repo survives untracked); the claim's Repository MR then **adopts** it
   (external-name match) — no image loss. If the repo is empty, just let the `ecr` unit destroy it and the
   claim recreate it.
3. Apply the teams.hcl-consumer units (`iam-roles`, `eks`, `policy`; `ecr`, `s3-shared` on platform) — the
   `migrated` flag withdraws the team's Terragrunt infra. Then commit the team's claim YAML to
   `gitops/tenant-claims/preprod/` (PR → ArgoCD syncs it).
4. The namespace is briefly destroyed then recreated by the claim; ArgoCD resyncs the app once it returns
   (downtime is acceptable on preprod). Verify as above + confirm `terragrunt plan` is clean.

> After the overnight scale-to-zero/restore, ArgoCD may fail to reach preprod (`ComparisonError … i/o
> timeout`) because the preprod EKS API ENI IPs changed and the cross-vpc-dns record went stale — re-apply
> `platform/.../cross-vpc-dns` to refresh, then hard-refresh the ArgoCD app.

---

## Troubleshooting

| Symptom | Cause / fix |
| ------- | ----------- |
| `XTenant` stuck `SYNCED=False` | An MR failed — `kubectl describe xtenant <team>` and `kubectl get managed \| grep <team>`; check the failing MR's `Synced` condition message (often a missing provisioner IAM verb or a Kyverno denial). |
| `XTenant` SYNCED but `READY=False` | A managed resource isn't Ready yet (provider reconcile lag) or a K8s `Object` was rejected by Kyverno — check the Object's status. |
| AWS MR 403 (e.g. `eks:TagResource`, `iam:ListInstanceProfilesForRole`) | The `crossplane-provisioner-<cluster>` role is missing a verb — add it in the `crossplane` module's provisioner policy and apply. |
| Cross-account ECR MR `AccessDenied … sts:TagSession` | The platform `crossplane-ecr-provisioner` trust must allow `sts:TagSession` (not just `AssumeRole`); the preprod provisioner needs both too. |
| Claim creation denied by `restrict-tenant-control-plane` | The claim must be applied by a **platform** principal — ArgoCD (the `platform-tenants` Application, assuming the `ArgoCD` IAM role) is that principal, excluded from the S1 backstop; a tenant principal is denied. |
| Per-team `restrict-images`/`restrict-route-hostnames` appear twice / `AlreadyExists` | The team is in both the claim and the `policy` unit's non-migrated set — ensure `migrated = true` in `teams.hcl`. |
