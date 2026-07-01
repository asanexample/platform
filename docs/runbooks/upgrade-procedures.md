# Runbook: Upgrade Procedures

> **Version pins:** `infra/live/aws/_versions.hcl`
> **Module source:** `infra/modules/` (monorepo, HEAD)
>
> **Last reviewed:** 2026-05-28

---

## Table of Contents

1. [Version Management Overview](#version-management-overview)
2. [Upgrading Helm Charts](#upgrading-helm-charts)
3. [Upgrading EKS](#upgrading-eks)
4. [Upgrading Cilium](#upgrading-cilium)
5. [Upgrading ArgoCD](#upgrading-argocd)
6. [Upgrading cert-manager](#upgrading-cert-manager)
7. [Upgrading Tailscale Operator](#upgrading-tailscale-operator)
8. [Upgrading OpenTofu / Terragrunt](#upgrading-opentofu--terragrunt)
9. [Rollback](#rollback)

---

## Version Management Overview

All Helm chart versions are pinned in a single file:

```text
infra/live/aws/_versions.hcl
```

Current versions:

| Component | Version | Pin location |
|-----------|---------|--------------|
| EKS (Kubernetes) | 1.35 | `infra/modules/aws/eks/variables.tf` (default) |
| Cilium | 1.19.4 | `_versions.hcl` → `helm_versions.cilium` |
| ArgoCD | 9.5.14 | `_versions.hcl` → `helm_versions.argocd` |
| cert-manager | 1.17.1 | `_versions.hcl` → `helm_versions.cert_manager` |
| external-dns | 1.16.1 | `_versions.hcl` → `helm_versions.external_dns` |
| external-secrets | 0.14.3 | `_versions.hcl` → `helm_versions.external_secrets` |
| Kyverno | 3.8.1 | `_versions.hcl` → `helm_versions.kyverno` |
| Tailscale Operator | 1.96.5 | `_versions.hcl` → `helm_versions.tailscale_operator` |
| kube-prometheus-stack | 87.5.0 | `_versions.hcl` → `helm_versions.kube_prometheus_stack` (platform hub; the same pin also drives the preprod prometheus-agent spoke) |
| Grafana Mimir | 6.0.6 | `_versions.hcl` → `helm_versions.mimir` (platform only) |
| Falco | 9.0.0 | `_versions.hcl` → `helm_versions.falco` (preprod only) |
| vCluster | 0.34.1 | `infra/modules/vcluster/variables.tf` (deferred, ADR-033) |

Modules are sourced from the monorepo at HEAD (`get_repo_root()`). All
environments share the same module code -- there is no per-environment
version pinning for modules today.

> The observability stack (`kube-prometheus-stack`, `mimir`) runs **on the platform** cluster
> (the hub) and Falco **only on preprod** today, so their upgrades skip the "preprod first, then
> platform" sequencing — apply on the cluster where they run. (Note the `kube_prometheus_stack`
> pin is **shared**: it also versions the preprod **prometheus-agent** spoke collector, so a bump
> touches both — verify the spoke chart's compatibility too.) They otherwise follow the general Helm
> chart procedure below. Mimir is a StatefulSet-heavy chart (ingester/store-gateway/compactor on PVCs);
> size `helm_timeout` generously and watch the operator-driven StatefulSet rollouts.

---

## Upgrading Helm Charts

This is the general procedure for any Helm-managed component. Component-
specific sections below note additional constraints.

### Step 1: Check Release Notes

Review the upstream changelog for breaking changes, deprecations, and
required CRD updates between your current version and the target.

### Step 2: Update the Version Pin

Edit `infra/live/aws/_versions.hcl`:

```hcl
helm_versions = {
  cilium = "1.20.0"   # was 1.19.4
  # ... other versions unchanged
}
```

### Step 3: Plan in Preprod First

```bash
cd infra/live/aws/preprod/us-east-1/platform/<component>
AWS_PROFILE=management terragrunt plan
```

Review the plan. Helm upgrades typically show the release being updated
in-place. Watch for:

- **CRD changes** -- some charts require CRDs to be updated separately.
- **Value removals** -- deprecated values that will cause errors.
- **Resource replacements** -- `forces replacement` on critical resources.

### Step 4: Apply to Preprod

```bash
AWS_PROFILE=management terragrunt apply
```

Verify the component is healthy before proceeding to platform.

### Step 5: Apply to Platform

```bash
cd infra/live/aws/platform/us-east-1/platform/<component>
AWS_PROFILE=management terragrunt plan
AWS_PROFILE=management terragrunt apply
```

### Step 6: Commit

Commit the version bump to `_versions.hcl` on a feature branch and open
a PR.

---

## Upgrading EKS

EKS upgrades are higher-risk than Helm upgrades. The control plane and
node groups must be upgraded in sequence.

### Constraints

- EKS supports upgrading one minor version at a time (e.g., 1.35 → 1.36,
  not 1.35 → 1.37).
- Node groups must match or be one minor version behind the control plane.
- Cilium compatibility must be verified against the target Kubernetes
  version.
- EKS managed add-ons (coredns) must be compatible with the target
  version.

### Step 1: Check Compatibility

1. [EKS release calendar](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html)
2. [Cilium compatibility matrix](https://docs.cilium.io/en/stable/network/kubernetes/compatibility/)
3. EKS managed add-on versions: `aws eks describe-addon-versions --kubernetes-version <target>`

### Step 2: Update the Control Plane

Edit `infra/modules/aws/eks/variables.tf` default or override in the
live unit:

```hcl
kubernetes_version = "1.36"
```

Apply the EKS unit (control plane only):

```bash
cd infra/live/aws/preprod/us-east-1/platform/eks
AWS_PROFILE=management terragrunt apply
```

This takes 15-25 minutes. The API server remains available during the
upgrade.

### Step 3: Update EKS Add-ons

After the control plane is upgraded, update managed add-ons:

```bash
cd infra/live/aws/preprod/us-east-1/platform/eks-addons
AWS_PROFILE=management terragrunt apply
```

### Step 4: Update Node Groups

Node groups perform a rolling update. New nodes launch with the target
version; old nodes drain and terminate.

```bash
cd infra/live/aws/preprod/us-east-1/platform/node-groups
AWS_PROFILE=management terragrunt apply
```

Monitor node rollout:

```bash
kubectl get nodes -w
```

Wait for all nodes to show the new version before proceeding.

### Step 5: Validate

```bash
kubectl get nodes -o wide
kubectl get pods -A | grep -v Running | grep -v Completed
```

### Step 6: Repeat for Platform

Follow the same sequence (eks → eks-addons → node-groups) for the
platform cluster.

### Order Summary

```text
preprod eks → preprod eks-addons → preprod node-groups → validate
platform eks → platform eks-addons → platform node-groups → validate
```

---

## Upgrading Cilium

Cilium is the CNI (BYOCNI mode). A failed Cilium upgrade can break all
pod networking.

### Constraints

- EKS uses BYOCNI (`bootstrap_self_managed_addons = false`), so Cilium
  is the only CNI. If Cilium goes down, pods lose connectivity.
- `kubeProxyReplacement = true` -- there is no kube-proxy fallback.
- Hubble TLS uses the `helm` method to avoid post-install hook issues.
- Cilium supports upgrading one minor version at a time.

### Pre-Upgrade Checklist

```bash
# Check current Cilium status
kubectl -n kube-system exec ds/cilium -- cilium status

# Check Cilium version on all nodes
kubectl -n kube-system get pods -l k8s-app=cilium -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\n"}{end}'
```

### Upgrade Procedure

1. Update `_versions.hcl`:

   ```hcl
   cilium = "1.20.0"
   ```

2. Plan and review carefully:

   ```bash
   cd infra/live/aws/preprod/us-east-1/platform/cilium
   AWS_PROFILE=management terragrunt plan
   ```

3. Apply to preprod:

   ```bash
   AWS_PROFILE=management terragrunt apply
   ```

4. Validate connectivity:

   ```bash
   # All cilium pods should restart and become ready
   kubectl -n kube-system get pods -l k8s-app=cilium -w

   # Verify connectivity
   kubectl -n kube-system exec ds/cilium -- cilium status
   kubectl -n kube-system exec ds/cilium -- cilium connectivity test
   ```

5. Check Hubble:

   ```bash
   kubectl -n kube-system get pods -l k8s-app=hubble-relay
   ```

6. Apply to platform cluster after preprod is stable.

### If Cilium Fails to Start

```bash
# Check cilium agent logs
kubectl -n kube-system logs ds/cilium --tail=100

# Check for policy drops
kubectl -n kube-system exec ds/cilium -- cilium monitor --type drop
```

If the upgrade is unrecoverable, roll back the version in `_versions.hcl`
and re-apply.

---

## Upgrading ArgoCD

ArgoCD runs on the platform cluster and manages deployments to preprod.

### Constraints

- ArgoCD SSO uses **Keycloak OIDC** (ADR-053/059; embedded Dex is off,
  `dex_enabled = false`). The OIDC config is injected via `argocd-cm`
  (`oidc.config`), so an ArgoCD upgrade should not disturb it -- but
  verify the login still works after the upgrade.
- ArgoCD cluster secrets (preprod connection) must remain valid after
  upgrade.
- CRDs (Application, AppProject, ApplicationSet) may change between
  major versions.

### Pre-Upgrade

```bash
# Check current version
kubectl -n argocd get pods -l app.kubernetes.io/name=argocd-server \
  -o jsonpath='{.items[0].spec.containers[0].image}'

# Back up ArgoCD secrets
kubectl -n argocd get secret argocd-secret -o yaml > /tmp/argocd-secret-backup.yaml
```

### Upgrade Procedure

1. Update `_versions.hcl`:

   ```hcl
   argocd = "9.6.0"
   ```

2. Apply:

   ```bash
   cd infra/live/aws/platform/us-east-1/platform/argocd
   AWS_PROFILE=management terragrunt plan
   AWS_PROFILE=management terragrunt apply
   ```

3. Validate:

   ```bash
   # All ArgoCD pods running
   kubectl -n argocd get pods

   # SSO login works
   # Open https://argocd.aws.refplat.org and verify OIDC login via Keycloak

   # Cluster connections healthy
   argocd cluster list

   # Applications syncing
   argocd app list
   ```

---

## Upgrading cert-manager

### Constraints

- CRDs often change between minor versions. The Helm chart installs CRDs
  by default (`installCRDs: true` via the module).
- ClusterIssuers and Certificates should not be disrupted during upgrade.

### Upgrade Procedure

1. Update `_versions.hcl`:

   ```hcl
   cert_manager = "1.18.0"
   ```

2. Apply to preprod first, then platform:

   ```bash
   cd infra/live/aws/preprod/us-east-1/platform/cert-manager
   AWS_PROFILE=management terragrunt plan
   AWS_PROFILE=management terragrunt apply
   ```

3. Validate:

   ```bash
   # Pods healthy
   kubectl -n cert-manager get pods

   # Existing certificates still valid
   kubectl get certificates -A
   kubectl get clusterissuers

   # Test renewal (if a cert is close to expiry)
   kubectl describe certificate <name> -n <namespace>
   ```

---

## Upgrading Tailscale Operator

### Constraints

- The operator runs as a subnet router advertising `10.100.0.0/16`.
  An upgrade restarts the pod, briefly interrupting VPN routing.
- Uses `TS_USERSPACE=true` via ProxyClass to avoid conflict with
  Cilium eBPF.

### Upgrade Procedure

1. Warn users that VPN access will briefly drop.

2. Update `_versions.hcl`:

   ```hcl
   tailscale_operator = "1.98.0"
   ```

3. Apply:

   ```bash
   cd infra/live/aws/platform/us-east-1/platform/tailscale
   AWS_PROFILE=management terragrunt plan
   AWS_PROFILE=management terragrunt apply
   ```

4. Validate:

   ```bash
   # Operator pod running
   kubectl -n tailscale-system get pods

   # Subnet router advertising routes (Connector is cluster-scoped)
   kubectl get connector -o yaml

   # VPN connectivity
   tailscale status
   ```

---

## Upgrading OpenTofu / Terragrunt

These are local CLI tools, not deployed infrastructure. The canonical
versions of all CLI tools (`tofu`, `terragrunt`, `kubectl`, `helm`,
`awscli`) are pinned in **`/.tool-versions`** — the single source of
truth read by local dev (mise/asdf), CI, and the self-hosted runner
image. Bump the version there so every consumer stays in lock-step.

### OpenTofu

1. Check the [OpenTofu changelog](https://github.com/opentofu/opentofu/releases).
2. Update the version constraint in `infra/root.hcl` if needed.
3. Install the new version locally.
4. Run `tofu fmt -check -recursive infra/modules/` to catch syntax changes.
5. Test with `terragrunt plan` on a non-critical unit before applying widely.

### Terragrunt

1. Check the [Terragrunt changelog](https://github.com/gruntwork-io/terragrunt/releases).
2. Install the new version.
3. Run `terragrunt hcl fmt --check` to validate configuration syntax.
4. Test with `terragrunt plan` on a non-critical unit.

---

## Rollback

### Helm Chart Rollback

Revert the version in `_versions.hcl` to the previous value and re-apply:

```bash
# Edit _versions.hcl to restore the previous version
cd infra/live/aws/<env>/us-east-1/platform/<component>
AWS_PROFILE=management terragrunt apply
```

### EKS Rollback

EKS control plane upgrades **cannot be rolled back**. If an upgrade
causes issues:

1. Roll back node groups to the previous AMI (if the old version is still
   within the supported skew).
2. Address the incompatibility at the application or add-on level.
3. Contact AWS Support if the control plane is in a degraded state.

### General Principles

- Always upgrade preprod first and validate before touching platform.
- Keep the previous version noted in the PR description for quick revert.
- If multiple components need upgrading, do them one at a time with
  validation between each.
