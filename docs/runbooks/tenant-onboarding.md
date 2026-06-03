# Runbook: Tenant Team Onboarding (Preprod EKS)

> **On-call scope:** Platform Engineering
> **Model:** Tenants are provisioned by the Crossplane **Tenant control plane** via an `XTenant` claim (BACK
> stack P3, [ADR-046](../adrs/046-back-stack-for-developer-self-service.md) /
> [ADR-048](../adrs/048-federated-per-cluster-crossplane.md)). A single claim provisions the complete tenant.
> The old Terragrunt path (`tenants`/`pod-identity`/`s3-shared` units, the `tenant` module) is **retired**.
> **Live configurations:**
>
> - `infra/live/aws/preprod/us-east-1/platform/tenant-claims/terragrunt.hcl` — **the claim** (primary)
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
- [ ] The team's **`Dev-<team>` SSO permission set** exists in `identity-center` (mgmt account) — required
      for the `DeveloperAccess-<team>` role trust to resolve to real users. Add it there if new.
- [ ] The crossplane control plane is healthy: `kubectl --context preprod get providers.pkg.crossplane.io`
      (all Healthy) and `kubectl --context preprod get xrd xtenants.platform.refplat.org` (Established).

---

## Onboarding a new team

### Step 1 — Author the `XTenant` claim

Add an entry to `tenants` in
`infra/live/aws/preprod/us-east-1/platform/tenant-claims/terragrunt.hcl`. The map value **is** the claim
spec:

```hcl
tenants = {
  # ...existing teams...
  charlie = {
    team      = "charlie"
    hostnames = ["charlie.preprod.aws.refplat.org"] # must be in the team's allow-list (drives restrict-route-hostnames)
    apps = {
      api = { repoPath = "k8s/preprod", preview = true } # → ECR repo team-charlie/api
    }
    aws = {
      serviceAccount = "app-charlie" # the named SA the app's pods run as
      # Generic IAM granted to Pod-team-charlie (capped by the deny-escalation boundary). Empty = no AWS perms.
      # NOTE: S3 buckets are NOT created (that was a demo) — grant access to existing resources here.
      policyStatements = []
    }
    # resourceQuota omitted → XRD defaults (cpu 4, memory 8Gi, pods 20, …)
    # developerAccess omitted → enabled by default
  }
}
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

```bash
cd infra/live/aws/preprod/us-east-1/platform/tenant-claims
AWS_PROFILE=management terragrunt apply        # creates the XTenant; Crossplane reconciles it

# Then apply the units that read teams.hcl for delivery + supply chain:
cd ../policy        && AWS_PROFILE=management terragrunt apply   # per-team verify-* policies
cd ../../../../platform/us-east-1/platform/argocd-apps && AWS_PROFILE=management terragrunt apply  # ArgoCD app
```

The `XTenant` reconciles asynchronously (~1–2 min) — `terragrunt apply` returns before it's Ready.

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

1. Remove the team's entry from the `tenant-claims` unit and `terragrunt apply` — the `XTenant` is deleted
   and the Composition tears down **every** managed resource (the namespace + AWS, both accounts) via
   finalizers.
2. Remove the team from `teams.hcl` and apply `policy` + `argocd-apps` (drops its verify-* policies + ArgoCD
   app).
3. Remove the `Dev-<team>` permission set from `identity-center` if the team is fully gone.
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
   `migrated` flag withdraws the team's Terragrunt infra. Then apply `tenant-claims`.
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
| Claim creation denied by `restrict-tenant-control-plane` | The claim must be applied by a **platform** principal (PlatformDeployer via the `tenant-claims` unit), not a tenant principal. |
| Per-team `restrict-images`/`restrict-route-hostnames` appear twice / `AlreadyExists` | The team is in both the claim and the `policy` unit's non-migrated set — ensure `migrated = true` in `teams.hcl`. |
