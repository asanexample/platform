# Runbook: Deploying Applications to Preprod EKS

> **Severity:** Low (routine deployment)
> **On-call scope:** Development Teams / Platform Engineering
> **Related:** [EKS Cluster Access](eks-cluster-access.md),
> [ArgoCD SSO](argocd-sso.md), [Tailscale VPN](tailscale-vpn.md)
>
> **Last reviewed:** 2026-05-27

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Repository Structure](#repository-structure)
4. [Sample Manifests](#sample-manifests)
5. [Pushing Images to ECR](#pushing-images-to-ecr)
6. [ArgoCD Sync and Delivery](#argocd-sync-and-delivery)
7. [Debugging Deployments](#debugging-deployments)
8. [Common Issues](#common-issues)

---

## Overview

Applications deploy to the preprod EKS cluster (`preprod-use1-eks` in
account `620830101009`) via ArgoCD running on the platform cluster. The
delivery flow:

```text
Developer pushes code
  -> GitHub Actions builds image -> pushes to ECR (platform account)
  -> Developer updates manifests in k8s/preprod/
  -> ArgoCD auto-syncs manifests to preprod cluster
  -> Cilium Gateway API routes traffic via HTTPRoute
  -> cert-manager provisions TLS, external-dns creates DNS records
```

Teams are assigned either a **namespace** (`team-<name>`) or a
**vCluster** (`vc-<name>`) in `infra/live/aws/preprod/us-east-1/platform/teams.hcl`.
This runbook covers namespace-mode tenants. vCluster tenants follow the
same manifest patterns but deploy into their virtual cluster.

---

## Prerequisites

### 1. AWS SSO Access

You need an SSO profile for the preprod account with the
`DeveloperAccess` role. Add to `~/.aws/config`:

```ini
[profile preprod-dev]
sso_session = centric
sso_account_id = 620830101009
sso_role_name = PowerUserAccess

[sso-session centric]
sso_start_url = https://d-9067aa6520.awsapps.com/start
sso_region = us-east-1
sso_registration_scopes = sso:account:access
```

Log in:

```bash
aws sso login --profile preprod-dev
```

### 2. kubectl Access

Configure kubeconfig for the preprod cluster:

```bash
platctl kubeconfig --env preprod
```

Or manually:

```bash
AWS_PROFILE=preprod-dev aws eks update-kubeconfig \
  --name preprod-use1-eks \
  --region us-east-1 \
  --role-arn arn:aws:iam::620830101009:role/DeveloperAccess
```

Verify access to your team namespace:

```bash
kubectl get pods -n team-alpha
```

### 3. Tailscale VPN (for ArgoCD UI)

The ArgoCD web UI is available at `https://argocd.aws.refplat.org` and
requires Tailscale VPN. See [Tailscale VPN runbook](tailscale-vpn.md)
for setup.

### 4. ArgoCD CLI (optional)

```bash
brew install argocd

argocd login argocd.aws.refplat.org --sso
```

---

## Repository Structure

ArgoCD watches each team's repo at the path configured in `teams.hcl`.
The default convention is `k8s/preprod/`:

```text
your-app-repo/
  k8s/
    preprod/
      deployment.yaml
      service.yaml
      httproute.yaml
      configmap.yaml        # optional
      external-secret.yaml  # optional (for secrets from AWS SM)
```

ArgoCD syncs all YAML files in this directory. Do not use
subdirectories -- the ArgoCD Application is configured with a flat path,
not recursive.

**Allowed resource kinds** (enforced by ArgoCD AppProject):

- ConfigMap, Secret, Service, ServiceAccount
- Deployment, StatefulSet, Job, CronJob
- HTTPRoute (Gateway API)
- ExternalSecret (External Secrets Operator)

Other resource kinds will be rejected by the AppProject whitelist.

---

## Sample Manifests

The examples below deploy a web application in the `team-alpha`
namespace with HTTPS ingress at `myapp.preprod.aws.refplat.org`.

### Deployment

```yaml
# k8s/preprod/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: team-alpha
  labels:
    app: myapp
spec:
  replicas: 2
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
        - name: myapp
          image: 829808296602.dkr.ecr.us-east-1.amazonaws.com/team-alpha/myapp:v1.0.0
          ports:
            - containerPort: 8080
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 512Mi
          livenessProbe:
            httpGet:
              path: /healthz
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 15
          readinessProbe:
            httpGet:
              path: /readyz
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 10
```

> **Important:** Always set explicit `resources.requests` and
> `resources.limits`. The namespace has a LimitRange that applies
> defaults (100m/128Mi request, 500m/512Mi limit) but explicit values
> are preferred. The namespace also has a ResourceQuota -- if your
> deployment exceeds the quota, pods will fail to schedule.

### Service

```yaml
# k8s/preprod/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: myapp
  namespace: team-alpha
spec:
  type: ClusterIP
  selector:
    app: myapp
  ports:
    - port: 80
      targetPort: 8080
      protocol: TCP
```

### HTTPRoute

```yaml
# k8s/preprod/httproute.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: myapp
  namespace: team-alpha
spec:
  parentRefs:
    - name: preprod-gateway
      namespace: default
      sectionName: https
  hostnames:
    - myapp.preprod.aws.refplat.org
  rules:
    - backendRefs:
        - name: myapp
          port: 80
```

The `preprod-gateway` Gateway lives in the `default` namespace with
GatewayClass `cilium`. It has two listeners:

- `https` (port 443) -- TLS termination with a wildcard cert for
  `*.preprod.aws.refplat.org` (Let's Encrypt DNS-01 via cert-manager)
- `http` (port 80) -- available but prefer `https`

Both listeners accept routes from all namespaces (`allowedRoutes.from: All`).

external-dns automatically creates a DNS record for the hostname in the
HTTPRoute. No manual Route53 configuration is needed.

---

## Pushing Images to ECR

Container images are stored in ECR in the **platform** account
(`829808296602`). The preprod account pulls cross-account via an ECR
repository policy.

### GitHub Actions (CI)

Use OIDC federation to authenticate GitHub Actions with AWS. The
workflow needs an IAM role in the platform account that trusts the
GitHub OIDC provider.

```yaml
# .github/workflows/build-push.yml
name: Build and Push

on:
  push:
    branches: [main]

permissions:
  id-token: write
  contents: read

env:
  ECR_REGISTRY: 829808296602.dkr.ecr.us-east-1.amazonaws.com
  ECR_REPO: team-alpha/myapp

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::829808296602:role/github-actions-ecr-push
          aws-region: us-east-1

      - name: Login to ECR
        id: ecr-login
        uses: aws-actions/amazon-ecr-login@v2

      - name: Build and push
        run: |
          IMAGE_TAG="${{ github.sha }}"
          docker build -t $ECR_REGISTRY/$ECR_REPO:$IMAGE_TAG .
          docker build -t $ECR_REGISTRY/$ECR_REPO:latest .
          docker push $ECR_REGISTRY/$ECR_REPO:$IMAGE_TAG
          docker push $ECR_REGISTRY/$ECR_REPO:latest
```

### Manual Push (Local)

```bash
# Authenticate to ECR in the platform account
aws sso login --profile platform
AWS_PROFILE=platform aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin 829808296602.dkr.ecr.us-east-1.amazonaws.com

# Tag and push
docker build -t 829808296602.dkr.ecr.us-east-1.amazonaws.com/team-alpha/myapp:v1.0.0 .
docker push 829808296602.dkr.ecr.us-east-1.amazonaws.com/team-alpha/myapp:v1.0.0
```

---

## ArgoCD Sync and Delivery

### Auto-Sync Behavior

ArgoCD Applications are configured with automated sync:

- **Self-heal:** if someone manually edits a resource in the cluster,
  ArgoCD reverts it to match the Git manifests
- **Prune:** resources removed from Git are deleted from the cluster
- **CreateNamespace=false:** ArgoCD does not create namespaces --
  namespaces are managed by Terraform via the `tenant` module

ArgoCD polls the repo every 3 minutes by default. After pushing
manifest changes to `main`, expect the sync to begin within 3 minutes.

### Manual Sync via UI

1. Connect to Tailscale VPN
2. Open `https://argocd.aws.refplat.org`
3. Log in via SSO (Identity Center)
4. Find your application (e.g. `alpha-app`)
5. Click **Sync** > **Synchronize**

### Manual Sync via CLI

```bash
# Sync your application
argocd app sync alpha-app

# Check sync status
argocd app get alpha-app

# View sync history
argocd app history alpha-app
```

### Checking Application Status

```bash
# List all applications
argocd app list

# Detailed status (shows out-of-sync resources)
argocd app get alpha-app

# View the live manifest diff
argocd app diff alpha-app
```

---

## Debugging Deployments

### Pod Status and Logs

```bash
# Check pod status
kubectl get pods -n team-alpha

# Describe a failing pod (shows events, scheduling failures)
kubectl describe pod -n team-alpha <pod-name>

# View logs
kubectl logs -n team-alpha <pod-name>

# Follow logs in real time
kubectl logs -n team-alpha <pod-name> -f

# View logs from a previous crash
kubectl logs -n team-alpha <pod-name> --previous

# Exec into a running container
kubectl exec -it -n team-alpha <pod-name> -- /bin/sh
```

### Deployment Rollout

```bash
# Check rollout status
kubectl rollout status deployment/myapp -n team-alpha

# View rollout history
kubectl rollout history deployment/myapp -n team-alpha

# Roll back (ArgoCD will detect drift and may re-sync)
kubectl rollout undo deployment/myapp -n team-alpha
```

> **Note:** Manual rollbacks are overridden by ArgoCD self-heal. To
> roll back, revert the manifest change in Git and let ArgoCD sync.

### Events

```bash
# Namespace events (sorted by time)
kubectl get events -n team-alpha --sort-by=.lastTimestamp

# Filter for warnings only
kubectl get events -n team-alpha --field-selector type=Warning
```

### ArgoCD Application Debugging

```bash
# Check sync status and health
argocd app get alpha-app

# View application events/conditions
argocd app get alpha-app -o yaml | grep -A 20 conditions

# Force a refresh (re-read from Git without syncing)
argocd app get alpha-app --refresh
```

### Network Debugging

```bash
# Verify the HTTPRoute is attached to the gateway
kubectl get httproute -n team-alpha

# Check gateway status
kubectl get gateway preprod-gateway -n default

# Verify the service has endpoints
kubectl get endpoints myapp -n team-alpha

# Test connectivity from within the cluster
kubectl run -n team-alpha debug --rm -it --image=busybox -- wget -qO- http://myapp.team-alpha.svc.cluster.local
```

### DNS and TLS

```bash
# Check if DNS record was created
dig myapp.preprod.aws.refplat.org

# Check certificate status
kubectl get certificate -n default

# Check cert-manager ClusterIssuer
kubectl get clusterissuer
kubectl describe clusterissuer letsencrypt-prod
```

---

## Common Issues

### ImagePullBackOff (Cross-Account ECR)

**Symptoms:** Pod stuck in `ImagePullBackOff` or `ErrImagePull`.

**Cause:** The preprod cluster cannot pull images from the platform
account ECR. The ECR repository policy must explicitly allow
cross-account pull from `620830101009`.

**Fix:**

```bash
# Verify the ECR repo policy allows cross-account access
AWS_PROFILE=platform aws ecr get-repository-policy \
  --repository-name team-alpha/myapp \
  --region us-east-1

# The policy must include a statement allowing ecr:GetDownloadUrlForLayer,
# ecr:BatchGetImage, and ecr:BatchCheckLayerAvailability for the
# preprod account root (arn:aws:iam::620830101009:root)
```

If the policy is missing, ask the platform team to add a cross-account
pull policy to the ECR repository.

Also verify the image tag exists:

```bash
AWS_PROFILE=platform aws ecr describe-images \
  --repository-name team-alpha/myapp \
  --region us-east-1 \
  --query 'imageDetails[*].imageTags' --output table
```

### NetworkPolicy Blocking Traffic

**Symptoms:** HTTPRoute is attached but requests time out or return 503.

**Cause:** Each tenant namespace has a default-deny ingress
NetworkPolicy. Traffic from the Cilium gateway (in the `default`
namespace) is allowed by the `allow-gateway-ingress` policy, but if that
policy is missing or misconfigured, traffic is blocked.

**Fix:**

```bash
# List network policies in your namespace
kubectl get networkpolicy -n team-alpha

# Expected policies:
#   default-deny-ingress      (blocks all ingress by default)
#   allow-gateway-ingress     (allows traffic from default namespace)
#   allow-dns-egress          (allows DNS + outbound)

# If allow-gateway-ingress is missing, contact the platform team.
# This policy is managed by Terraform (tenant module), not application manifests.
```

If you need pod-to-pod communication within the namespace, add an
intra-namespace NetworkPolicy to your manifests:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-intra-namespace
  namespace: team-alpha
spec:
  podSelector: {}
  policyTypes: [Ingress]
  ingress:
    - from:
        - podSelector: {}
```

### HTTPRoute Not Attaching to Gateway

**Symptoms:** HTTPRoute exists but shows no parent status, or traffic
does not reach the service.

**Cause:** Common misconfigurations:

1. Wrong `parentRef` gateway name or namespace
2. Hostname does not match the gateway listener wildcard
3. Missing `sectionName: https`

**Fix:**

```bash
# Check HTTPRoute status
kubectl describe httproute myapp -n team-alpha

# Verify parentRef values match exactly:
#   name: preprod-gateway
#   namespace: default
#   sectionName: https

# Verify hostname matches *.preprod.aws.refplat.org
```

### DNS Record Not Created

**Symptoms:** HTTPRoute is attached, but `dig myapp.preprod.aws.refplat.org`
returns NXDOMAIN.

**Cause:** external-dns creates DNS records from HTTPRoute hostnames.
It may take up to 5 minutes for DNS propagation.

**Fix:**

```bash
# Check external-dns logs for errors
kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns --tail=50

# Verify the Route53 hosted zone exists
AWS_PROFILE=preprod-dev aws route53 list-hosted-zones \
  --query 'HostedZones[?Name==`preprod.aws.refplat.org.`]'

# Force external-dns to re-evaluate (restart the pod)
kubectl rollout restart deployment -n external-dns external-dns
```

### TLS Certificate Stuck in Pending

**Symptoms:** Browser shows certificate error. Certificate resource
shows `Ready: False`.

**Cause:** cert-manager uses DNS-01 challenge via Route53. The
ClusterIssuer's IRSA role must have permissions to modify the Route53
hosted zone.

**Fix:**

```bash
# Check certificate status
kubectl get certificate -n default -o wide

# Check cert-manager logs
kubectl logs -n cert-manager -l app.kubernetes.io/name=cert-manager --tail=50

# Check the challenge status
kubectl get challenges -A

# Common causes:
# - Route53 permissions: cert-manager IRSA role cannot create TXT records
# - Rate limiting: Let's Encrypt rate limits (5 certs per domain per week)
# - DNS propagation: challenge TXT record not visible yet (wait and retry)
```

### ResourceQuota Exceeded

**Symptoms:** Pods stuck in `Pending`. Events show
`exceeded quota: tenant-quota`.

**Fix:**

```bash
# Check current quota usage
kubectl describe resourcequota tenant-quota -n team-alpha

# Either reduce resource requests in your deployment or ask the
# platform team to increase the quota in teams.hcl
```

### ArgoCD Sync Failed

**Symptoms:** Application shows `SyncFailed` or `OutOfSync` in the
ArgoCD UI.

**Fix:**

```bash
# Check sync status and error message
argocd app get alpha-app

# View the sync result details
argocd app get alpha-app -o yaml | grep -A 10 operationState

# Common causes:
# - Invalid YAML syntax in manifests
# - Resource kind not in AppProject whitelist
# - Namespace mismatch (manifest namespace != ArgoCD destination namespace)
# - RBAC: ArgoCD service account lacks permission for the resource type
```

Verify your manifest namespace matches the team namespace convention:

- Namespace mode: `team-<name>` (e.g. `team-alpha`)
- vCluster mode: `vc-<name>` (e.g. `vc-bravo`)
