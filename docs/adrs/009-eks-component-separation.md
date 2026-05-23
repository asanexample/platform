# ADR-009: EKS Component Separation

**Date:** 2026-05-23

**Status:** Accepted

## Context

EKS clusters are typically deployed as a single Terraform module that creates the cluster, node
groups, and managed add-ons in one apply. This works when using the default AWS VPC CNI, which is
pre-installed on every EKS cluster. However, the platform uses Cilium as CNI via BYOCNI (see
ADR-008), which creates a strict deployment ordering constraint:

1. The cluster must exist before Cilium can be installed (Cilium needs the API server).
2. Cilium must be running before node groups join (nodes need a CNI to configure pod networking).
3. Managed add-ons like CoreDNS must wait until both CNI and nodes are ready (add-on pods need
   the CNI to schedule and nodes to run on).

A single monolithic EKS module cannot express this ordering because Terraform applies all resources
in a module as a single unit. There's no way to say "create the cluster, wait for an external Helm
install, then create node groups."

### Alternatives Considered

**1. Monolithic module with provisioners.** Use `local-exec` provisioners on the EKS cluster
resource to install Cilium via `helm` CLI before node groups are created. This keeps everything in
one module but introduces shell dependencies (`helm`, `kubectl`, valid kubeconfig) into the
Terraform execution environment, makes the Cilium installation invisible to Terraform state, and
creates fragile error handling — a failed Helm install leaves the module in a partially applied
state that's difficult to recover from.

**2. Monolithic module with depends_on.** Create all resources in one module but use `depends_on`
between them. This doesn't work because Cilium is installed via a separate Helm provider, and
cross-module `depends_on` in Terraform only works within the same module. The Helm release for
Cilium needs its own provider configuration pointing at the cluster, which creates a circular
dependency if defined in the same module as the cluster.

**3. Separate Terragrunt units (chosen).** Split EKS deployment into four independent Terragrunt
units with explicit dependency ordering. Each unit is a focused module with its own state file,
provider configuration, and lifecycle. Terragrunt's `dependency` blocks enforce the ordering.

## Decision

Split EKS cluster deployment into four Terragrunt units, each backed by a dedicated module:

```text
eks → cilium → node-groups → eks-addons
```

### Unit Responsibilities

| Unit | Module | Creates | Why Separate |
|------|--------|---------|--------------|
| `eks` | `aws/eks` | EKS cluster, OIDC provider, KMS key, security group, access entries | Cluster must exist before CNI installation |
| `cilium` | `cilium` (shared) | Helm release for Cilium CNI, CRDs | CNI must be running before nodes join |
| `node-groups` | `aws/eks-node-group` | Managed node groups, node IAM role | Nodes need CNI to configure networking |
| `eks-addons` | `aws/eks-addons` | EKS managed add-ons (CoreDNS, etc.) | Add-on pods need CNI + nodes to schedule |

### EKS Cluster Configuration

The EKS module sets `bootstrap_self_managed_addons = false` to prevent AWS from installing the
default VPC CNI and kube-proxy on cluster creation. This is required for BYOCNI — if the default
CNI is installed, it conflicts with Cilium.

### Dependency Chain

Enforced via Terragrunt `dependency` blocks with `mock_outputs` for plan/destroy resilience:

```hcl
# node-groups/terragrunt.hcl
dependency "eks" {
  config_path = "../eks"
  mock_outputs = { cluster_id = "mock", cluster_endpoint = "https://mock" }
}

dependency "cilium" {
  config_path = "../cilium"
  mock_outputs = {}
}
```

### State Isolation

Each unit has its own Terraform state file, which means:

- Failures in one unit don't corrupt the state of others
- Units can be planned/applied independently after initial setup
- Destroy ordering is the reverse of apply ordering

## Consequences

**Positive:**

- Clean enforcement of BYOCNI ordering — impossible to accidentally create nodes before CNI is
  ready
- Independent lifecycle management — node groups can be scaled or reconfigured without touching
  the cluster or CNI
- EKS add-on versions can be updated independently of cluster version
- State isolation reduces blast radius of failed applies
- Each unit is small and focused, making it easier to understand and debug
- `mock_outputs` on all dependencies ensure `terragrunt destroy` works even when upstream units
  are already destroyed

**Negative:**

- Four Terragrunt units instead of one — more directories, more state files, more plan/apply
  cycles for initial cluster setup
- First-time deployment requires running units in order (though `terragrunt run-all apply`
  handles this automatically via the DAG)
- Developers must understand the dependency chain to troubleshoot deployment failures
- Changes that span multiple units (e.g., adding a new subnet that affects both networking and
  node groups) require coordinated applies

**Risks:**

- If Cilium is destroyed while node groups exist, nodes lose networking and all pods fail. The
  destroy ordering (node-groups before cilium) prevents this in normal operation, but a manual
  `terragrunt destroy` of the cilium unit alone would cause an outage. Mitigated by documentation
  and the manual destroy order in CLAUDE.md.
