# platctl validate — Shallow Infrastructure Health Checks

## Context

`platctl validate` is currently a stub. The command should verify that deployed infrastructure actually works — not just that Terraform state exists. Checks should be shallow ("is the pod Running") not deep ("can it issue a certificate"). When checks fail, output should include detailed diagnostics and suggested fixes.

---

## Check Categories

Seven check categories — four per-unit, three cross-cutting:

### 1. EKS Cluster Check (unit: `eks`)

- `aws eks describe-cluster --query cluster.status` → must be `ACTIVE`
- `kubectl get nodes` → all nodes `Ready`, report count
- On failure: show node names and conditions, suggest `kubectl describe node`

### 2. Kubernetes Workload Check

For units that deploy pods — verify expected pods exist and are Running with all containers ready.

| Unit | Namespace | Label selector |
|------|-----------|---------------|
| `cilium` | `kube-system` | `app.kubernetes.io/name=cilium-agent` |
| `eks-addons` | `kube-system` | `k8s-app=kube-dns` |
| `cert-manager` | `cert-manager` | — |
| `external-dns` | `external-dns` | — |
| `external-secrets` | `external-secrets` | — |
| `secret-stores` | `external-secrets` | `app.kubernetes.io/name=external-secrets` |
| `argocd` | `argocd` | — |
| `tailscale` | `tailscale-system` | — |

On failure: list unhealthy pods with their status and reason (e.g., `CrashLoopBackOff`, `ImagePullBackOff`), suggest `kubectl logs` / `kubectl describe pod`.

**Not workload checks** (no pods):

- `node-groups` → covered by EKS node count
- `argocd-clusters` → creates ArgoCD Application CRs, no pods
- `gateway-config` → covered by Gateway Health Check (#3)

### 3. Gateway Health Check (unit: `gateway-config`)

Validates the full ingress chain from GatewayClass down to NLB targets. Catches the exact failure modes we hit: missing GatewayClass, stuck Gateway, failed TLS, unhealthy NLB.

1. **GatewayClass exists**: `kubectl get gatewayclass cilium` → must exist with `Accepted: True`
2. **Gateway programmed**: `kubectl get gateway platform-gateway` → `Programmed: True`, not `Pending`/`Unknown`
3. **TLS certificate ready**: `kubectl get certificate platform-gateway-tls` → `Ready: True`
4. **NLB active with healthy targets**: resolve the Gateway's `status.addresses` hostname, check NLB state via `aws elbv2`

On failure — diagnostic chain:

- GatewayClass missing → "GatewayClass 'cilium' does not exist. Restart cilium-operator: `kubectl rollout restart deployment/cilium-operator -n kube-system`"
- Gateway not Programmed → show conditions, suggest checking GatewayClass and cilium-operator logs
- TLS cert not ready → show cert-manager reason (e.g., "rate limited, retry after X", "ACME challenge failed"), suggest `kubectl describe certificate`
- NLB unhealthy → show target health states, suggest checking node security groups and NodePort services

### 4. State Check (everything else)

For infra-only units: `networking`, `iam-roles`, `cloudtrail`, `route53`, `cloudflare-dns`, `transit-gateway`, `cross-vpc-dns`, `ssm-bastion`, `tailscale-admin`, `node-groups`, `argocd-clusters`.

Runs `terragrunt state list`, reports resource count. Skipped if state is empty.

### 5. Tailscale Connectivity Check (cross-cutting, per environment)

1. **Subnet router online**: `tailscale status --json` → find peer with matching hostname, verify `Online: true`
2. **Routes advertised**: verify `PrimaryRoutes` is non-empty
3. **Split DNS configured**: verify `*.eks.amazonaws.com` has a split DNS route to VPC resolver
4. **Private API reachable**: `kubectl --context <env> cluster-info` → confirms full chain works

On failure: show which step failed, suggest checking Tailscale admin console or running `tailscale status`.

### 6. IAM & Access Check (cross-cutting)

1. **SSO session valid**: `aws sts get-caller-identity --profile <profile>` for each configured profile
2. **PlatformDeployer assumable**: `aws sts assume-role` with PlatformDeployer ARN per account
3. **PlatformAdmin assumable**: `aws sts assume-role` with kubectl_role_arn from kubeconfig config
4. **State backend accessible**: `aws s3 ls` on state bucket

On failure: show the specific error (expired token, access denied, role not found), suggest `aws sso login --profile <name>`.

### 7. Endpoint Reachability Check (cross-cutting)

Verifies key service endpoints are reachable:

- **ArgoCD**: `https://argocd.aws.refplat.org/` → HTTP 200 or 302 (SSO redirect)
- Extensible for future endpoints

On failure: show HTTP status or connection error, check Gateway status and DNS resolution, suggest diagnostics.

---

## Output Format

```text
Validating platform (21 units)...

  ok platform/iam-roles                 14 resources in state
  ok platform/eks                       cluster ACTIVE, 3/3 nodes Ready
  ok platform/cilium                    3/3 pods ready in kube-system
  !! platform/cert-manager              1/3 pods ready in cert-manager
     → cert-manager-webhook-xxx: CrashLoopBackOff
     → Run: kubectl logs -n cert-manager cert-manager-webhook-xxx
  -- platform/cloudflare-dns            skipped (no state)

Gateway health:
  ok platform/gateway-config            GatewayClass accepted, Gateway programmed, TLS ready, NLB healthy
  !! platform/gateway-config            Gateway programmed, TLS not ready
     → Certificate platform-gateway-tls: rate limited (retry after 2026-05-27 22:02:53 UTC)
     → Run: kubectl describe certificate platform-gateway-tls -n default

Validating preprod (12 units)...
  ...

Tailscale connectivity:
  ok platform                           subnet router online, routes [10.100.0.0/16], API reachable
  ok preprod                            subnet router online, API reachable

IAM & access:
  ok management                         SSO session valid (<MGMT_ACCOUNT_ID>)
  ok platform                           PlatformDeployer assumable, PlatformAdmin assumable
  ok preprod                            PlatformDeployer assumable, PlatformAdmin assumable
  ok state-backend                      S3 bucket accessible

Endpoints:
  ok argocd                             https://argocd.aws.refplat.org/ → 302

Passed: 35  Failed: 1  Skipped: 2
```

Exit code 1 if any check fails (CI-friendly).

---

## Architecture

```text
internal/validate/           NEW PACKAGE
├── validate.go              CheckResult, UnitChecker interface, RunChecks, ResolveChecker
├── checks.go                StateCheck, EKSClusterCheck, K8sWorkloadCheck
├── gateway.go               GatewayHealthCheck — GatewayClass, Gateway status, TLS cert, NLB health
├── tailscale.go             TailscaleCheck — subnet router, routes, DNS, API reachability
├── access.go                IAMCheck — SSO session, role assumption, state backend
├── endpoints.go             EndpointCheck — HTTP reachability of service URLs
├── kube.go                  KubeClient interface + ExecKubeClient (kubectl wrapper)
└── validate_test.go         Tests with mocks for all check types
```

Separate from `engine/` — validate is a flat parallel fan-out with no DAG, state persistence, or failure propagation.

### Key Types

```go
type CheckResult struct {
    Unit    string
    Status  string        // "ok", "failed", "skipped"
    Message string        // one-line summary
    Details []string      // additional lines shown on failure (diagnostics, fix suggestions)
    Err     error
    Elapsed time.Duration
}

type UnitChecker interface {
    Check(ctx context.Context, unit *engine.Unit) CheckResult
}

type KubeClient interface {
    GetNodes(ctx context.Context, kubeCtx string) ([]NodeStatus, error)
    GetPods(ctx context.Context, kubeCtx string, namespace, labelSelector string) ([]PodStatus, error)
    GetGatewayClass(ctx context.Context, kubeCtx, name string) (*GatewayClassStatus, error)
    GetGateway(ctx context.Context, kubeCtx, namespace, name string) (*GatewayStatus, error)
    GetCertificate(ctx context.Context, kubeCtx, namespace, name string) (*CertificateStatus, error)
    ClusterInfo(ctx context.Context, kubeCtx string) error
}
```

### Parallel Execution

All checks run concurrently, bounded by `--concurrency` semaphore (default 8). No DAG ordering — checks are read-only.

---

## File Changes

| File | Action | Description |
|------|--------|-------------|
| `internal/validate/validate.go` | **Create** | CheckResult, UnitChecker, RunChecks, ResolveChecker |
| `internal/validate/checks.go` | **Create** | StateCheck, EKSClusterCheck, K8sWorkloadCheck |
| `internal/validate/gateway.go` | **Create** | GatewayHealthCheck (GatewayClass, Gateway, TLS cert, NLB) |
| `internal/validate/tailscale.go` | **Create** | TailscaleCheck |
| `internal/validate/access.go` | **Create** | IAMCheck, StateBackendCheck |
| `internal/validate/endpoints.go` | **Create** | EndpointCheck |
| `internal/validate/kube.go` | **Create** | KubeClient interface + ExecKubeClient |
| `internal/validate/validate_test.go` | **Create** | Tests with mocks |
| `internal/cli/validate.go` | **Modify** | Replace stub with real wiring |
| `internal/cloud/cloud.go` | **Modify** | Add DescribeEKSCluster to AWSClient |
| `internal/cloud/aws.go` | **Modify** | Implement DescribeEKSCluster |
| `README.md` | **Modify** | Update validate section |
| `ARCHITECTURE.md` | **Modify** | Add validate package docs |

---

## Configuration

Endpoint URLs and IAM role ARNs come from `.platctl.yaml`. Add a new top-level section:

```yaml
validate:
  endpoints:
    - name: argocd
      url: https://argocd.aws.refplat.org/
      env: platform
  iam:
    state_bucket: tfstate-mgmt-<MGMT_ACCOUNT_ID>
    state_role_arn: arn:aws:iam::<MGMT_ACCOUNT_ID>:role/TerraformStateAccess
    accounts:
      platform:
        id: "<PLATFORM_ACCOUNT_ID>"
        deployer_role: PlatformDeployer
      preprod:
        id: "<PREPROD_ACCOUNT_ID>"
        deployer_role: PlatformDeployer
```
