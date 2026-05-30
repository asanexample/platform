# Runbook: Tenant Team Onboarding (Preprod EKS)

> **On-call scope:** Platform Engineering
> **Live configurations:**
>
> - `infra/live/aws/preprod/us-east-1/platform/teams.hcl`
> - `infra/live/aws/preprod/us-east-1/platform/tenants/terragrunt.hcl`
> - `infra/live/aws/preprod/us-east-1/platform/iam-roles/terragrunt.hcl`
> - `infra/live/aws/preprod/us-east-1/platform/eks/terragrunt.hcl`
> - `infra/live/aws/mgmt/global/identity-center/terragrunt.hcl`
> - `infra/live/aws/platform/us-east-1/platform/ecr/terragrunt.hcl`
> - `infra/live/aws/platform/us-east-1/platform/argocd-apps/terragrunt.hcl`
> - `infra/live/aws/platform/us-east-1/platform/github-oidc/terragrunt.hcl`
>
> **Last reviewed:** 2026-05-29

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Isolation Mode](#isolation-mode)
3. [Onboarding Steps](#onboarding-steps)
4. [Verification Commands](#verification-commands)
5. [Offboarding](#offboarding)
6. [Troubleshooting](#troubleshooting)

---

## Prerequisites

Before starting, confirm the following:

- [ ] You have an active AWS SSO session for the **management** profile
  (`aws sso login --profile management`).
- [ ] Your SSO identity can assume **PlatformDeployer** in both the platform
  (<PLATFORM_ACCOUNT_ID>) and preprod (<PREPROD_ACCOUNT_ID>) accounts.
- [ ] You have `terragrunt`, `kubectl`, and `argocd` CLI tools installed.
- [ ] You have kubeconfig configured for the preprod cluster:

  ```bash
  AWS_PROFILE=management aws eks update-kubeconfig \
    --name preprod-use1-eks \
    --region us-east-1 \
    --role-arn arn:aws:iam::<PREPROD_ACCOUNT_ID>:role/PlatformAdmin
  ```

- [ ] You have the following information from the requesting team:
  - Team name (lowercase, alphanumeric + hyphens)
  - GitHub organization and repository name (under `asanexample/`)
  - Resource quota requirements (if non-default)
  - Whether apps need PR preview environments (`preview = true`)
  - Whether repos are private (requires ArgoCD credential template + GitHub
    token for PR previews — see ADR-032)
- [ ] You are working on a feature branch (not `main`).

---

## Isolation Mode

All teams use **namespace isolation** (`mode = "namespace"`). Each team gets a
`team-<name>` namespace with ResourceQuota, LimitRange, and Cilium NetworkPolicies.

| | **Namespace** (`mode = "namespace"`) |
|---|---|
| **What's created** | `team-<name>` namespace, ResourceQuota, LimitRange, NetworkPolicy |
| **Isolation level** | Namespace-scoped RBAC + NetworkPolicy |
| **CRD access** | Shared cluster CRDs only |
| **Resource overhead** | Minimal |
| **Default quotas** | 4 CPU, 8 Gi memory, 20 pods |
| **EKS access entry** | Per-team `DeveloperAccess-<name>` role, group-mapped to `team-<name>:developers` and bound (namespace-scoped) to `tenant-developer` (ADR-039) |

> **Note:** The tenant module also supports a `vcluster` mode for stronger
> isolation (CRD independence, virtual control plane), but this is currently
> **deferred** (ADR-033) because the open-source vCluster chart cannot sync
> HTTPRoute resources to the host cluster's Gateway.

---

## Onboarding Steps

All Terragrunt commands below assume `AWS_PROFILE=management` is set. Export it
once at the start of the session:

```bash
export AWS_PROFILE=management
```

### Step 1: Add Team to `teams.hcl`

Edit `infra/live/aws/preprod/us-east-1/platform/teams.hcl` and add the new team
to the `teams` map:

```hcl
locals {
  teams = {
    # Existing teams
    alpha = {
      mode = "namespace"
      apps = {
        demo = {
          repo_url  = "https://github.com/asanexample/app-alpha"
          repo_path = "k8s/preprod"
          preview   = true
        }
      }
    }
    bravo = {
      mode = "namespace"
      apps = {
        demo = {
          repo_url  = "https://github.com/asanexample/app-bravo"
          repo_path = "k8s/preprod"
          preview   = false
        }
      }
    }

    # NEW: Add your team here
    charlie = {
      mode = "namespace"
      apps = {
        api = {
          repo_url  = "https://github.com/asanexample/app-charlie"
          repo_path = "k8s/preprod"
          preview   = true
        }
      }
    }
  }

  namespace_teams = { for k, v in local.teams : k => v if v.mode == "namespace" }
  vcluster_teams  = { for k, v in local.teams : k => v if v.mode == "vcluster" }
}
```

Each team can have multiple apps. Each app entry has `repo_url` and `repo_path`
telling ArgoCD where to find the Kubernetes manifests. Set `preview = true` to
enable PR preview environments (see ADR-032). Confirm these values with the team
before proceeding.

Teams with multiple services add multiple app entries:

```hcl
charlie = {
  mode = "namespace"
  apps = {
    api = {
      repo_url  = "https://github.com/asanexample/charlie-api"
      repo_path = "k8s/preprod"
      preview   = true
    }
    worker = {
      repo_url  = "https://github.com/asanexample/charlie-worker"
      repo_path = "k8s/preprod"
    }
  }
}
```

### Step 2: Add ECR Repository

Edit `infra/live/aws/platform/us-east-1/platform/ecr/terragrunt.hcl` and add a
repository entry for the new team:

```hcl
repositories = {
  "team-alpha/demo"    = {}
  "team-bravo/demo"    = {}
  "team-charlie/api"   = {}   # NEW
}
```

ECR repos follow `team-<team>/<app>` naming (e.g., `team-charlie/api` for the
`api` app owned by team `charlie`). Create one ECR repo per app entry in
`teams.hcl`.

> **Kyverno (ADR-014):** the per-team image-registry policy (`restrict-images-team-<team>`,
> admitting only `…/team-<team>/*`) is generated automatically — the `policy` unit derives
> `tenant_registry_map` from `teams.hcl`, so no extra step is needed for the new team. It applies in
> `Audit` until the cluster is flipped to `Enforce` (see [kyverno-break-glass](kyverno-break-glass.md)).

The ECR module lives in the **platform** account (<PLATFORM_ACCOUNT_ID>). Cross-account
pull access for preprod (<PREPROD_ACCOUNT_ID>) and prod (<PROD_ACCOUNT_ID>) is already
configured via the `pull_account_ids` input.

### Step 3: Add the team to the GitHub OIDC unit

Edit `infra/live/aws/platform/us-east-1/platform/github-oidc/terragrunt.hcl` and
add the team to the `teams` map:

```hcl
locals {
  teams = {
    alpha   = { github_repo = "app-alpha" }
    bravo   = { github_repo = "app-bravo" }
    charlie = { github_repo = "app-charlie" }   # NEW
  }
}
```

This generates a dedicated `github-actions-ecr-push-charlie` IAM role that trusts
**only** `asanexample/app-charlie` (OIDC `sub`) and can push **only** to that team's
`team-charlie/*` ECR repos (per-team isolation — ADR-039 / issue #60). The team's
GitHub Actions workflow must then assume `arn:aws:iam::<PLATFORM_ACCOUNT_ID>:role/github-actions-ecr-push-charlie`.

### Step 4: Apply Changes

Apply changes across both accounts. The order matters -- `ecr` and `github-oidc`
are independent, but `tenants` must come before `argocd-apps` since ArgoCD targets
the tenant namespace.

**Preprod account** (IAM role + EKS access entry + tenant resources). Apply
`iam-roles` first so the per-team `DeveloperAccess-<name>` role exists before the
`eks` access entry references it, and before `tenants` creates the RoleBinding:

```bash
cd infra/live/aws/preprod/us-east-1/platform/iam-roles
terragrunt apply

cd ../eks
terragrunt apply

cd ../tenants
terragrunt apply
```

**Platform account** (ECR, GitHub OIDC, ArgoCD apps):

```bash
cd infra/live/aws/platform/us-east-1/platform/ecr
terragrunt apply

cd ../github-oidc
terragrunt apply

cd ../argocd-apps
terragrunt apply
```

**What each apply does:**

| Unit | Account | Resources Created |
|---|---|---|
| `iam-roles` | preprod | `DeveloperAccess-charlie` IAM role (trusted by the `Dev-charlie` SSO set) |
| `eks` | preprod | Group-mapped access entry for `DeveloperAccess-charlie` → group `team-charlie:developers` |
| `tenants` | preprod | Namespace (`team-charlie`) with PSA labels, ResourceQuota, LimitRange, NetworkPolicy, CiliumNetworkPolicy, and the `tenant-developers` RoleBinding |
| `ecr` | platform | ECR repository `team-charlie/api` |
| `github-oidc` | platform | Updates OIDC trust policy to include new repo |
| `argocd-apps` | platform | ArgoCD Application targeting the team's Git repo |

### Step 5: Add the Team's SSO Permission Set + Group (IaC)

Identity Center is managed as code. Edit
`infra/live/aws/mgmt/global/identity-center/terragrunt.hcl` and add a per-team
permission set, group, and account assignment (mirroring the `Dev-alpha` /
`Developers-alpha` entries):

```hcl
# permission_sets
"Dev-charlie" = {
  description      = "Developer access for team charlie (preprod)"
  session_duration = "PT4H"
  managed_policies = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
  inline_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "AssumeTeamDeveloperRole"
      Effect   = "Allow"
      Action   = "sts:AssumeRole"
      Resource = "arn:aws:iam::${dependency.organizations.outputs.account_ids["Preprod"]}:role/DeveloperAccess-charlie"
    }]
  })
}

# groups
"Developers-charlie" = { description = "Developers for team charlie" }

# account_assignments
{ account_id = dependency.organizations.outputs.account_ids["Preprod"], permission_set = "Dev-charlie", group = "Developers-charlie" },
```

Apply from the management account:

```bash
cd infra/live/aws/mgmt/global/identity-center
terragrunt apply
```

Then add the team's developers to the `Developers-charlie` group (via SCIM or the
SSO console). After that, a developer runs `aws sso login` with the `Dev-charlie`
permission set, assumes `DeveloperAccess-charlie`, and gets kubectl access scoped
to `team-charlie` only. The `Dev-charlie` set also grants account-wide read-only
AWS access (preprod posture).

### Step 6: Verify

See the full [Verification Commands](#verification-commands) section below.

---

## Verification Commands

Run these checks after completing the onboarding steps. Replace `charlie` with
the actual team name.

### Namespace Exists

```bash
kubectl get namespace team-charlie
```

### Resource Quota Applied

```bash
kubectl get resourcequota tenant-quota -n team-charlie -o yaml
# Verify: requests.cpu=4, requests.memory=8Gi, pods=20
```

### Network Policies in Place

```bash
kubectl get networkpolicy -n team-charlie
# Expected: default-deny-ingress, allow-gateway-ingress, allow-dns-egress
# (allow-dns-egress denies egress to 169.254.169.254/32 — the IMDS endpoint)

kubectl get ciliumnetworkpolicy -n team-charlie
# Expected: allow-gateway-envoy
```

### Pod Security Admission Labels

```bash
kubectl get namespace team-charlie -o jsonpath='{.metadata.labels}' | tr ',' '\n' | grep pod-security
# Expected: enforce=baseline, warn=restricted, audit=restricted
```

### EKS Access Entry + RBAC

```bash
# The per-team access entry maps DeveloperAccess-charlie to the team's K8s group
aws eks describe-access-entry \
  --cluster-name preprod-use1-eks \
  --principal-arn arn:aws:iam::<PREPROD_ACCOUNT_ID>:role/DeveloperAccess-charlie \
  --region us-east-1 \
  --query 'accessEntry.kubernetesGroups'
# Verify: ["team-charlie:developers"]

# The RoleBinding granting that group edit rights exists in the team namespace
kubectl get rolebinding tenant-developers -n team-charlie -o yaml
# Verify: roleRef -> ClusterRole/tenant-developer, subject Group team-charlie:developers
```

### ArgoCD Application Created

```bash
# Via CLI (requires ArgoCD login)
argocd app list | grep charlie

# Via kubectl on the platform cluster
kubectl get application -n argocd -l "platform.refplat.org/tenant=charlie"
```

### ECR Repository Accessible

```bash
aws ecr describe-repositories \
  --repository-names team-charlie/api \
  --region us-east-1 \
  --profile platform
```

### GitHub OIDC Trust Policy

```bash
# Per-team role: trusts only the team's repo and pushes only to team-charlie/*
aws iam get-role \
  --role-name github-actions-ecr-push-charlie \
  --profile platform \
  --query 'Role.AssumeRolePolicyDocument' | grep app-charlie
aws iam get-role-policy \
  --role-name github-actions-ecr-push-charlie --policy-name github-actions-ecr-push-charlie-inline \
  --profile platform --query 'PolicyDocument.Statement[?Sid==`ECRPush`].Resource'  # only team-charlie/*
```

---

## Offboarding

To remove a team, reverse the onboarding process. Coordinate with the team to
confirm all workloads are drained before proceeding.

### Checklist

- [ ] Notify the team of the offboarding date and confirm they have migrated or
  backed up any data.
- [ ] Remove the team entry from `teams.hcl`.
- [ ] Apply `tenants` to destroy the namespace and its resources:

  ```bash
  cd infra/live/aws/preprod/us-east-1/platform/tenants
  AWS_PROFILE=management terragrunt apply
  ```

- [ ] Apply `eks` to remove the team's group-mapped access entry:

  ```bash
  cd infra/live/aws/preprod/us-east-1/platform/eks
  AWS_PROFILE=management terragrunt apply
  ```

- [ ] Apply `iam-roles` to destroy the team's `DeveloperAccess-<name>` role:

  ```bash
  cd infra/live/aws/preprod/us-east-1/platform/iam-roles
  AWS_PROFILE=management terragrunt apply
  ```

- [ ] Apply `argocd-apps` to remove the ArgoCD Application:

  ```bash
  cd infra/live/aws/platform/us-east-1/platform/argocd-apps
  AWS_PROFILE=management terragrunt apply
  ```

- [ ] Remove the ECR repository from `ecr/terragrunt.hcl` and apply. Note: this
  deletes all images in the repository. Confirm the team no longer needs them.

  ```bash
  cd infra/live/aws/platform/us-east-1/platform/ecr
  AWS_PROFILE=management terragrunt apply
  ```

- [ ] Remove the repo from `github-oidc/terragrunt.hcl` and apply:

  ```bash
  cd infra/live/aws/platform/us-east-1/platform/github-oidc
  AWS_PROFILE=management terragrunt apply
  ```

- [ ] Remove the team's `Dev-<name>` permission set, `Developers-<name>` group, and
  account assignment from `identity-center/terragrunt.hcl` and apply:

  ```bash
  cd infra/live/aws/mgmt/global/identity-center
  AWS_PROFILE=management terragrunt apply
  ```

- [ ] Commit all changes on a feature branch and open a PR.

---

## Troubleshooting

### `terragrunt apply` fails on `tenants` with "Unauthorized"

The Kubernetes provider cannot reach the EKS API. Confirm:

1. You have an active SSO session: `aws sts get-caller-identity --profile management`
2. The PlatformDeployer role exists in preprod: check `iam-roles` unit output.
3. If the cluster API is private-only, connect via Tailscale or SSM tunnel first
   (see [EKS Cluster Access](eks-cluster-access.md)).

### Namespace exists but ArgoCD app shows "Missing"

The `argocd-apps` unit runs on the **platform** cluster and targets the preprod
cluster via `argocd-clusters`. Verify:

1. The ArgoCD cluster secret for preprod is healthy:
   `argocd cluster list | grep preprod`
2. The `repo_url` in `teams.hcl` is correct and the repo is accessible to ArgoCD.
3. The `repo_path` directory exists in the team's repository.

### Developer cannot assume their DeveloperAccess-<team> role

1. Confirm the `Dev-<team>` permission set, `Developers-<team>` group, and assignment
   were applied (Step 5), and the user is a member of that group.
2. Verify the role's trust policy allows the team's SSO permission set — the
   `aws:PrincipalArn` condition must match `AWSReservedSSO_Dev-<team>_*`.
3. Check the team's group-mapped access entry exists:

   ```bash
   aws eks describe-access-entry \
     --cluster-name preprod-use1-eks \
     --principal-arn arn:aws:iam::<PREPROD_ACCOUNT_ID>:role/DeveloperAccess-<team> \
     --region us-east-1
   ```

4. If the developer authenticates but is forbidden, confirm the `tenant-developers`
   RoleBinding exists in `team-<team>` (the `tenants` unit creates it) and its subject
   group matches the access entry's `kubernetesGroups`.

### ECR push from GitHub Actions fails with "Not Authorized"

1. Verify the team is in the `teams` map in `github-oidc/terragrunt.hcl` (which
   generates `github-actions-ecr-push-<team>`).
2. Confirm the workflow assumes the **per-team** role ARN
   (`github-actions-ecr-push-<team>`), not the old shared `github-actions-ecr-push`
   (removed in #60), and that its trust includes the repo:

   ```bash
   aws iam get-role --role-name github-actions-ecr-push-<team> --profile platform \
     --query 'Role.AssumeRolePolicyDocument'
   ```

3. Check the GitHub Actions workflow uses the correct (per-team) role ARN and region.
4. Ensure the ECR repository name in the push step matches `ecr/terragrunt.hcl`
   (format: `team-<name>/app`) and is under the calling team's `team-<team>/*` prefix.

### Pods stuck in Pending

1. Check node capacity: `kubectl describe nodes | grep -A5 "Allocated resources"`
2. Verify the `team-<name>` namespace resource quota has not been exhausted:
   `kubectl describe resourcequota tenant-quota -n team-<name>`
3. Ensure Cilium is healthy: `cilium status`
