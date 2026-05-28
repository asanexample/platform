# Runbook: Tenant Team Onboarding (Preprod EKS)

> **On-call scope:** Platform Engineering
> **Live configurations:**
>
> - `infra/live/aws/preprod/us-east-1/platform/teams.hcl`
> - `infra/live/aws/preprod/us-east-1/platform/tenants/terragrunt.hcl`
> - `infra/live/aws/preprod/us-east-1/platform/eks/terragrunt.hcl`
> - `infra/live/aws/platform/us-east-1/platform/ecr/terragrunt.hcl`
> - `infra/live/aws/platform/us-east-1/platform/argocd-apps/terragrunt.hcl`
> - `infra/live/aws/platform/us-east-1/platform/github-oidc/terragrunt.hcl`
>
> **Last reviewed:** 2026-05-27

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Choosing Isolation Mode](#choosing-isolation-mode)
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
  (829808296602) and preprod (620830101009) accounts.
- [ ] You have `terragrunt`, `kubectl`, and `argocd` CLI tools installed.
- [ ] You have kubeconfig configured for the preprod cluster:

  ```bash
  AWS_PROFILE=management aws eks update-kubeconfig \
    --name preprod-use1-eks \
    --region us-east-1 \
    --role-arn arn:aws:iam::620830101009:role/PlatformAdmin
  ```

- [ ] You have the following information from the requesting team:
  - Team name (lowercase, alphanumeric + hyphens)
  - GitHub organization and repository name (under `gangster/`)
  - Desired isolation mode (namespace or vCluster)
  - Resource quota requirements (if non-default)
- [ ] You are working on a feature branch (not `main`).

---

## Choosing Isolation Mode

Teams are onboarded in one of two isolation modes. The choice is recorded in
`teams.hcl` and determines what the `tenants` module provisions.

| | **Namespace** (`mode = "namespace"`) | **vCluster** (`mode = "vcluster"`) |
|---|---|---|
| **What's created** | `team-<name>` namespace, ResourceQuota, LimitRange, NetworkPolicy | `vc-<name>` namespace with a full vCluster (virtual control plane) |
| **Isolation level** | Namespace-scoped RBAC + NetworkPolicy | Virtual cluster with its own API server, etcd, scheduler |
| **CRD access** | Shared cluster CRDs only | Team can install their own CRDs inside the vCluster |
| **Resource overhead** | Minimal | ~0.5 CPU / 1 Gi per vCluster control plane |
| **Best for** | Standard microservice teams, simple workloads | Teams needing cluster-admin, custom operators, or CRD-heavy stacks |
| **Default quotas** | 4 CPU, 8 Gi memory, 20 pods | Managed by vCluster isolation settings |
| **EKS access entry** | DeveloperAccess scoped to `team-<name>` | DeveloperAccess scoped to `vc-<name>` |

**Recommendation:** Start with `namespace` unless the team has an explicit need for
cluster-level resources. Migrating from namespace to vCluster later requires
redeploying workloads but no data loss.

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
      mode      = "namespace"
      repo_url  = "https://github.com/gangster/app-alpha"
      repo_path = "k8s/preprod"
    }
    bravo = {
      mode      = "vcluster"
      repo_url  = "https://github.com/gangster/app-bravo"
      repo_path = "k8s/preprod"
    }

    # NEW: Add your team here
    charlie = {
      mode      = "namespace"
      repo_url  = "https://github.com/gangster/app-charlie"
      repo_path = "k8s/preprod"
    }
  }

  namespace_teams = { for k, v in local.teams : k => v if v.mode == "namespace" }
  vcluster_teams  = { for k, v in local.teams : k => v if v.mode == "vcluster" }
}
```

The `repo_url` and `repo_path` tell ArgoCD where to find the team's Kubernetes
manifests. Confirm these values with the team before proceeding.

### Step 2: Add ECR Repository

Edit `infra/live/aws/platform/us-east-1/platform/ecr/terragrunt.hcl` and add a
repository entry for the new team:

```hcl
repositories = {
  "team-alpha/app"   = {}
  "team-bravo/app"   = {}
  "team-charlie/app" = {}   # NEW
}
```

The ECR module lives in the **platform** account (829808296602). Cross-account
pull access for preprod (620830101009) and prod (554518885123) is already
configured via the `pull_account_ids` input.

### Step 3: Add GitHub Repository to OIDC Role

Edit `infra/live/aws/platform/us-east-1/platform/github-oidc/terragrunt.hcl` and
add the team's repository to the `github_repos` list:

```hcl
github_repos = ["app-alpha", "app-bravo", "app-charlie"]   # NEW: app-charlie
```

This grants the `github-actions-ecr-push` OIDC role permission to push images
from the new repository's GitHub Actions workflows.

### Step 4: Apply Changes

Apply changes across both accounts. The order matters -- `ecr` and `github-oidc`
are independent, but `tenants` must come before `argocd-apps` since ArgoCD targets
the tenant namespace.

**Preprod account** (tenants + EKS access entries):

```bash
cd infra/live/aws/preprod/us-east-1/platform/tenants
terragrunt apply

cd ../eks
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
| `tenants` | preprod | Namespace (`team-charlie` or `vc-charlie`), ResourceQuota, LimitRange, NetworkPolicy |
| `eks` | preprod | Updates DeveloperAccess entry with new namespace scope |
| `ecr` | platform | ECR repository `team-charlie/app` |
| `github-oidc` | platform | Updates OIDC trust policy to include new repo |
| `argocd-apps` | platform | ArgoCD Application targeting the team's Git repo |

### Step 5: Grant Identity Center Access

Add the team's Identity Center group to the **DeveloperAccess** permission set
assignment for the preprod account (620830101009). This is done in the AWS SSO
console:

1. Open **IAM Identity Center** in the management account.
2. Navigate to **AWS accounts** > select **preprod** (620830101009).
3. Click **Assign users or groups**.
4. Select the team's group (e.g., `Team-Charlie-Developers`).
5. Choose the **DeveloperAccess** permission set.
6. Confirm the assignment.

After assignment, team members can run `aws sso login --profile preprod` and
assume the DeveloperAccess role, which grants namespace-scoped kubectl access.

### Step 6: Verify

See the full [Verification Commands](#verification-commands) section below.

---

## Verification Commands

Run these checks after completing the onboarding steps. Replace `charlie` with
the actual team name.

### Namespace / vCluster Exists

```bash
# Namespace-mode team
kubectl get namespace team-charlie

# vCluster-mode team
kubectl get namespace vc-charlie
kubectl get pods -n vc-charlie   # vCluster control plane pods should be Running
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
```

### EKS Access Entry Updated

```bash
aws eks list-associated-access-policies \
  --cluster-name preprod-use1-eks \
  --principal-arn arn:aws:iam::620830101009:role/DeveloperAccess \
  --region us-east-1 \
  --query 'associatedAccessPolicies[].accessScope'
# Verify: team-charlie (or vc-charlie) appears in the namespaces list
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
  --repository-names team-charlie/app \
  --region us-east-1 \
  --profile platform
```

### GitHub OIDC Trust Policy

```bash
aws iam get-role \
  --role-name github-actions-ecr-push \
  --profile platform \
  --query 'Role.AssumeRolePolicyDocument' | grep app-charlie
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

- [ ] Apply `eks` to remove the namespace from the DeveloperAccess scope:

  ```bash
  cd infra/live/aws/preprod/us-east-1/platform/eks
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

- [ ] Remove the Identity Center group assignment for the team from the preprod
  account in the AWS SSO console.
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

### Developer cannot assume DeveloperAccess role

1. Confirm the Identity Center group assignment was completed (Step 5).
2. Verify the user is a member of the correct Identity Center group.
3. Check the EKS access entry includes the team's namespace:

   ```bash
   aws eks describe-access-entry \
     --cluster-name preprod-use1-eks \
     --principal-arn arn:aws:iam::620830101009:role/DeveloperAccess \
     --region us-east-1
   ```

### ECR push from GitHub Actions fails with "Not Authorized"

1. Verify the repo name is in the `github_repos` list in `github-oidc/terragrunt.hcl`.
2. Confirm the OIDC trust policy includes the repo:

   ```bash
   aws iam get-role --role-name github-actions-ecr-push --profile platform \
     --query 'Role.AssumeRolePolicyDocument'
   ```

3. Check the GitHub Actions workflow uses the correct role ARN and region.
4. Ensure the ECR repository name in the push step matches the name in
   `ecr/terragrunt.hcl` (format: `team-<name>/app`).

### vCluster pods stuck in Pending

1. Check node capacity: `kubectl describe nodes | grep -A5 "Allocated resources"`
2. Verify the `vc-<name>` namespace resource quota has not been exhausted.
3. Ensure Cilium is healthy: `cilium status` (vCluster pods need CNI to schedule).
