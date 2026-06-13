# Runbook: Environment Onboarding (Preprod EKS)

> **On-call scope:** Platform Engineering
> **Model:** Environments are provisioned by the Crossplane **Environment control plane** via an `XEnvironment`
> claim (ADR-067; BACK stack lineage [ADR-046](../adrs/046-back-stack-for-developer-self-service.md) /
> [ADR-048](../adrs/048-federated-per-cluster-crossplane.md)). A single claim provisions one complete environment
> (a Product at a Stage, optionally for a Customer). The old Terragrunt path (`environments`/`pod-identity`/`s3-shared`
> units, the per-team `environment`/`tenant` module) is **retired**.
> **Live configurations:**
>
> - `gitops/environments/<team>/<product>/<stage>[-<customer>].yaml` — **the claim** (one `XEnvironment`, synced
>   by ArgoCD)
> - `gitops/products/<team>/<product>.yaml` — the Product registry entry (repo + domains; delivery + supply-chain
>   identities derive from it, ADR-069)
> - `gitops/teams/<team>.yaml` — the git-native `Team` CR (SSO group + envelope, ADR-063)
> - `infra/live/aws/mgmt/global/identity-center/terragrunt.hcl` — the team's `Dev-<team>` SSO permission set
> - `infra/live/aws/platform/us-east-1/platform/argocd-apps/terragrunt.hcl` — app delivery (ArgoCD)
> - `infra/live/aws/platform/us-east-1/platform/github-oidc/terragrunt.hcl` — app CI OIDC (signing)
>
> **Last reviewed:** 2026-06-12

See [Crossplane Environment API](../architecture/crossplane-environment-api.md) for the XRD schema, what the
Composition provisions, and the claim lifecycle.

---

## Table of Contents

1. [What a claim provisions](#what-a-claim-provisions)
2. [Prerequisites](#prerequisites)
3. [Onboarding a new environment](#onboarding-a-new-environment)
4. [Verification](#verification)
5. [Offboarding](#offboarding)
6. [Troubleshooting](#troubleshooting)

---

## What a claim provisions

One `XEnvironment` claim → the Composition reconciles the **complete** environment. The provisioned unit is a
Product at a Stage; its namespace is `<team>-<product>-<stage>` (pooled) or `<team>-<product>-<customer>-<stage>`
(per-customer):

- **Kubernetes:** the `<team>-<product>-<stage>` namespace (labels `platform.refplat.org/{team,product,stage,tier}`),
  the `environment-quota` ResourceQuota, a LimitRange, default-deny + allow NetworkPolicies, CiliumNetworkPolicies,
  the `<namespace>:developers` RoleBinding (→ ClusterRole `environment-developer`), and the per-**Product** Kyverno
  `restrict-images` (`team-<team>/<product>-*`) + `restrict-route-hostnames` policies.
- **AWS (preprod), per Service:** the `Pod-<team>-<product>-[<customer>-]<stage>-<svc>` IAM role (capped by the
  `environment-permissions-boundary-<cluster>` boundary) + an EKS Pod Identity association binding the Service's
  named ServiceAccount; the `DeveloperAccess-<team>` IAM role + EKS access entry → the `<namespace>:developers`
  group.
- **AWS (platform account, cross-account), per Service:** the `team-<team>/<product>-<svc>` ECR repo + pull policy.

**Not** provisioned by the claim (still platform-owned / separate): the cosign/SLSA
`verify-images`/`verify-attestations` policies (the `policy` unit), the `Dev-<team>` SSO permission set
(`identity-center`), and app delivery (the per-Product ArgoCD ApplicationSet, `argocd-apps`).

---

## Prerequisites

- [ ] Active AWS SSO session for the **management** profile (`aws sso login --profile management`).
- [ ] Your SSO identity can assume **PlatformDeployer** in the preprod and platform accounts.
- [ ] `terragrunt` + `kubectl` configured; preprod reachable (Tailscale for kubectl).
- [ ] The **Team** (`gitops/teams/<team>.yaml`, ADR-063) and **Product** (`gitops/products/<team>/<product>.yaml`,
      ADR-069) already exist. The Team CR carries the envelope that bounds the environment; the Product carries the
      repo + domains delivery derives from. If onboarding a brand-new product, add those registry entries first.
- [ ] If the team's developers need cluster/AWS access, plan to add their **AWS Identity Center** wiring —
      the `Dev-<team>` permission set + `Developers-<team>` group + assignment + users. This is partly
      manual (per-user invite/MFA, or external-IdP group management); see
      [Step 3](#step-3--grant-developer-access-aws-identity-center). The claim's `DeveloperAccess-<team>`
      role trusts the `Dev-<team>` SSO principal, so the role can exist before this — but no human can use it
      until Identity Center is wired up.
- [ ] The crossplane control plane is healthy: `kubectl --context preprod get providers.pkg.crossplane.io`
      (all Healthy) and `kubectl --context preprod get xrd xenvironments.platform.refplat.org` (Established).

---

## Onboarding a new environment

### Step 1 — Author the `XEnvironment` claim

Create `gitops/environments/<team>/<product>/<stage>[-<customer>].yaml` (a single `XEnvironment`) via PR. The
file **is** the claim:

```yaml
apiVersion: platform.refplat.org/v1beta1
kind: XEnvironment
metadata:
  # CLUSTER-scoped, so the name must be globally unique — team+product+stage prefixed, matching the namespace.
  name: charlie-api-dev
spec:
  team: charlie
  product: api
  stage: dev # dev | test | uat | staging | prod (must be in the Team envelope's allowedStages)
  tier: standard # standard | elevated | pci | hipaa (must be in allowedTiers)
  # Route hostnames are DERIVED, not declared (ADR-060): each Service gets <product>-<team>-<stage>.<baseDomain> —
  # here api-charlie-dev.preprod.aws.refplat.org — plus a preview wildcard. The Composition derives the
  # restrict-route-hostnames allow-list and the per-Product ApplicationSet injects the same host into the
  # HTTPRoute, so app repos do NOT hardcode it. Add a `spec.domains` alias ONLY for an extra vanity host
  # (ADR-061), e.g.:
  #   domains:
  #     - host: charlie.preprod.aws.refplat.org
  services:
    web:
      serviceAccount: app-charlie # the named SA the app's pods run as; Pod Identity binds it
      preview: true # → preview environments; ECR repo team-charlie/api-web
      # image omitted until the first CI digest-bump promotes it into k8s/overlays/<stage> (first-deploy state).
      # Generic IAM granted to this Service's Pod-Identity role, under permissions.aws.policyStatements. Empty =
      # no AWS perms. Existing resources only (no buckets are created for you). DENY-SET-VALIDATED (ADR-062 §4,
      # #282) at CI + admission: the iam/sts/organizations/account services and bare `*`/`*:*` wildcards are
      # REJECTED; everything else (e.g. s3:GetObject, sqs:*, dynamodb:*) is allowed and additionally capped by the
      # AWS permissions boundary at runtime. Example of a compliant statement:
      #   permissions:
      #     aws:
      #       policyStatements:
      #         - sid: ReadTeamBucket
      #           actions: ["s3:GetObject", "s3:ListBucket"]
      #           resources: ["arn:aws:s3:::team-charlie-*", "arn:aws:s3:::team-charlie-*/*"]
  # quota omitted → XRD defaults (cpu 4, memory 8Gi, pods 20, …), capped by the Team envelope's quotaCap
  # lifecycle.phase omitted → active
```

### Step 2 — Apply

The claim is the single delivery source — there is **no separate `teams.hcl` to edit** (retired, ADR-069). The
delivery + supply-chain Terragrunt units (`argocd-apps`, `policy`, `github-oidc`) derive everything they need
(app repo, ECR push identity, cosign subjects, route-hostname allow-list) from the **Product** registry
(`spec.repo` + `spec.domains`) and the environment claims by `fileset`+`yamldecode` over `gitops/products/` and
`gitops/environments/`.

Open a PR with the claim YAML (`gitops/environments/charlie/api/dev.yaml`) — the path is CODEOWNERS-gated and
passes the **v3 gitops Gate** (envelope check: stage/tier/quota within the Team envelope). On merge, the
per-Product ArgoCD ApplicationSet syncs the `XEnvironment` to the preprod cluster (`selfHeal` + `prune` +
ServerSideApply) and the Composition reconciles it (~1–2 min). **No Terragrunt, no `terragrunt apply`** for the
claim itself.

Then apply the delivery + supply-chain units so they pick up the new Product/environment:

```bash
cd infra/live/aws/preprod/us-east-1/platform/policy && AWS_PROFILE=management terragrunt apply          # per-product verify-* policies
cd ../../../../platform/us-east-1/platform/argocd-apps && AWS_PROFILE=management terragrunt apply        # ArgoCD app delivery
cd ../github-oidc && AWS_PROFILE=management terragrunt apply                                             # app CI ECR-push OIDC role
```

### Step 3 — Grant developer access (AWS Identity Center)

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

# kubectl, scoped to their environment namespace (DeveloperAccess-charlie → <namespace>:developers RBAC)
aws eks update-kubeconfig --name preprod-use1-eks --region us-east-1 \
  --role-arn arn:aws:iam::<preprod-account>:role/DeveloperAccess-charlie --profile charlie-dev
kubectl get pods -n charlie-api-dev    # works; other namespaces are denied
```

The `Dev-charlie` permission set itself only grants account-wide **read** + `sts:AssumeRole` into
`DeveloperAccess-charlie`; all cluster authority is the namespace-scoped RBAC the claim bound to
`charlie-api-dev:developers` (ADR-039/040).

---

## Verification

```bash
# The claim + its managed resources
kubectl --context preprod get xenvironment charlie-api-dev        # SYNCED=True READY=True
kubectl --context preprod get managed | grep charlie-api-dev      # all Object + aws.upbound.io MRs Ready

# Kubernetes side
kubectl --context preprod get ns charlie-api-dev
kubectl --context preprod get resourcequota,rolebinding -n charlie-api-dev
kubectl --context preprod get clusterpolicy | grep charlie-api    # restrict-* (claim) + verify-* (policy unit)

# AWS side
aws iam get-role --role-name Pod-charlie-api-dev-web --profile preprod                    # boundary + tags
aws eks describe-access-entry --cluster-name preprod-use1-eks \
  --principal-arn arn:aws:iam::<preprod>:role/DeveloperAccess-charlie --profile preprod   # → charlie-api-dev:developers
aws ecr describe-repositories --repository-names team-charlie/api-web --profile platform   # cross-account repo
```

A compliant workload referencing `…/team-charlie/api-web:<tag>` should admit; a cross-product image is denied by
`restrict-images-charlie-api`.

---

## Offboarding

Removing an environment hard-deletes its namespace, so prefer the safe two-step path in the
[environment deprovisioning runbook](environment-deprovisioning.md) (decommission → grace → purge). The raw
teardown is:

1. Remove the environment's `gitops/environments/<team>/<product>/<stage>[-<customer>].yaml` via PR — on merge,
   the per-Product ArgoCD ApplicationSet prunes the `XEnvironment` and the Composition cascades the teardown of
   **every** managed resource (the namespace + AWS, both accounts) via finalizers. ECR repos are retained
   (`deletionPolicy: Orphan`).
2. If retiring the whole Product, also remove `gitops/products/<team>/<product>.yaml`, then apply
   `policy` + `argocd-apps` + `github-oidc` — with the Product gone they no longer derive it, so its verify-*
   policies, ApplicationSet, and ECR-push role are dropped.
3. If the team is fully gone, remove its `gitops/teams/<team>.yaml` and its Identity Center wiring from the
   `identity-center` unit (the `Dev-<team>` permission set, `Developers-<team>` group, its `users`, and the
   `account_assignments` entry) and `terragrunt apply` from the mgmt account. With an external IdP, also remove
   the group/members there. (Terraform deletes the SSO objects; no separate console step is needed to
   *deprovision*, unlike the manual *activation* on onboarding.)
4. Verify: `kubectl get xenvironment <name>` (NotFound), `aws iam get-role --role-name Pod-<team>-<product>-<stage>-<svc>`
   (NoSuchEntity); the ECR repo remains in the platform account.

---

## Troubleshooting

| Symptom | Cause / fix |
| ------- | ----------- |
| `XEnvironment` stuck `SYNCED=False` | An MR failed — `kubectl describe xenvironment <name>` and `kubectl get managed \| grep <name>`; check the failing MR's `Synced` condition message (often a missing provisioner IAM verb or a Kyverno denial). |
| `XEnvironment` SYNCED but `READY=False` | A managed resource isn't Ready yet (provider reconcile lag) or a K8s `Object` was rejected by Kyverno — check the Object's status. |
| AWS MR 403 (e.g. `eks:TagResource`, `iam:ListInstanceProfilesForRole`) | The `crossplane-provisioner-<cluster>` role is missing a verb — add it in the `crossplane` module's provisioner policy and apply. |
| Cross-account ECR MR `AccessDenied … sts:TagSession` | The platform `crossplane-ecr-provisioner` trust must allow `sts:TagSession` (not just `AssumeRole`); the preprod provisioner needs both too. |
| Claim creation denied by `restrict-environment-control-plane` | The claim must be applied by a **platform** principal — ArgoCD (the per-Product ApplicationSet, assuming the `ArgoCD` IAM role) is that principal, excluded from the S1 backstop; an environment principal is denied. |
| Claim rejected by `restrict-environment-envelope` | The claim's `stage`/`tier`/`quota` is outside the Team envelope (`gitops/teams/<team>.yaml`) — widen the envelope (admin PR) or fix the claim. |
| Per-product `restrict-images`/`restrict-route-hostnames` appear twice / `AlreadyExists` | A Product is owned by both the Composition (claim) and the `policy` unit's non-migrated path. Every Product with an environment claim is auto-migrated (`policy` derives `migrated_products` from the registries); confirm the Product has entries under `gitops/products/` + `gitops/environments/`. |
