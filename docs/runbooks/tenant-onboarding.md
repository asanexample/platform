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
| **EKS access entry** | DeveloperAccess scoped to `team-<name>` |

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
          repo_url  = "https://github.com/gangster/app-alpha"
          repo_path = "k8s/preprod"
          preview   = true
        }
      }
    }
    bravo = {
      mode = "namespace"
      apps = {
        demo = {
          repo_url  = "https://github.com/gangster/app-bravo"
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
          repo_url  = "https://github.com/gangster/app-charlie"
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
      repo_url  = "https://github.com/gangster/charlie-api"
      repo_path = "k8s/preprod"
      preview   = true
    }
    worker = {
      repo_url  = "https://github.com/gangster/charlie-worker"
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

The ECR module lives in the **platform** account (829808296602). Cross-account
pull access for preprod (620830101009) and prod (554518885123) is already
configured via the `pull_account_ids` input.

### Step 3: Add GitHub Repository to OIDC Role

Edit `infra/live/aws/platform/us-east-1/platform/github-oidc/terragrunt.hcl` and
add the team's repository to the `github_repos` list:

```hcl
github_repos  = ["app-alpha", "app-bravo", "app-charlie"]   # NEW: app-charlie
github_events = ["pull_request"]   # enables PR preview OIDC auth
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
| `tenants` | preprod | Namespace (`team-charlie`), ResourceQuota, LimitRange, NetworkPolicy, CiliumNetworkPolicy |
| `eks` | preprod | Updates DeveloperAccess entry with new namespace scope |
| `ecr` | platform | ECR repository `team-charlie/api` |
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

kubectl get ciliumnetworkpolicy -n team-charlie
# Expected: allow-gateway-envoy
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
  --repository-names team-charlie/api \
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

### Pods stuck in Pending

1. Check node capacity: `kubectl describe nodes | grep -A5 "Allocated resources"`
2. Verify the `team-<name>` namespace resource quota has not been exhausted:
   `kubectl describe resourcequota tenant-quota -n team-<name>`
3. Ensure Cilium is healthy: `cilium status`
