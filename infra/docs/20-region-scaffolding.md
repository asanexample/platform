# Region Scaffolding

## Overview

A new region is added by creating its Terragrunt directory tree under an environment and
filling in two region-level config files plus the workload units. There is **no scaffolding
tool yet** — regions are scaffolded by copying an existing region and editing it. This page
documents that process; an automated `platctl` target is planned.

## What a region looks like

The Terragrunt hierarchy (see [Configuration Hierarchy](../../docs/architecture/config-hierarchy.md))
layers from the cloud root down to each unit:

```text
infra/live/aws/<env>/                 env.hcl            # account ID, env tags
infra/live/aws/<env>/<region>/        region.hcl         # region name + abbreviation
                                      network.hcl        # vpc_cidr, azs, subnet tiers, pod_cidr
infra/live/aws/<env>/<region>/<workload>/  workload.hcl  # workload name, compliance_tier
                                           teams.hcl     # (environment clusters) team/app identity
infra/live/aws/<env>/<region>/<workload>/<module>/  terragrunt.hcl  # unit inputs + deps
```

`_base.hcl` loads every layer and exposes it to units via `include.base.locals.*`. State is
keyed by directory path (`live/aws/<env>/<region>/<workload>/<module>/terraform.tfstate`), so
a new region gets isolated state automatically.

## The two region-level files

**`region.hcl`** — region identity:

```hcl
locals {
  region      = "us-west-2"
  region_abbv = "usw2"        # used in resource names (e.g. eks-platform-usw2)
  region_tags = { Region = "us-west-2" }
}
```

**`network.hcl`** — CIDR allocation (the authoritative source, per
[CIDR Allocation](06-cidr-allocation.md)):

```hcl
locals {
  vpc_cidr = "10.1xx.0.0/16"   # the env's /16; regions take sequential /21s within it
  azs      = ["us-west-2a", "us-west-2b", "us-west-2c"]

  # Cilium overlay pod CIDR — per-cluster /16 from the reserved 10.240.0.0/14 supernet,
  # non-overlapping across clusters (ClusterMesh-ready). Distinct from the VPC and the
  # EKS service CIDR (172.20.0.0/16).
  pod_cidr = "10.24x.0.0/16"

  subnet_tiers = { /* kubernetes, endpoints, firewall, services, public, transit */ }
  subnets      = { /* computed from vpc_cidr + azs via cidrsubnet() */ }
  address_space = [local.vpc_cidr]
}
```

Subnets are computed with `cidrsubnet()` — only `vpc_cidr` and `azs` are hand-set.

## Process (manual)

1. **Copy** an existing region directory:
   `cp -r infra/live/aws/<env>/us-east-1 infra/live/aws/<env>/<new-region>`.
2. **Edit `region.hcl`** — `region`, `region_abbv`, `region_tags`.
3. **Edit `network.hcl`** — `vpc_cidr` (next free /21 in the env's /16), `azs` for the new
   region, and a non-overlapping `pod_cidr` for any cluster in this region.
4. **Review the workload units** — most inputs derive from `include.base.locals.*` and need
   no change, but check anything region-specific (AZ-derived subnet selectors, etc.).
5. **Plan before apply** — `terragrunt run --all plan` from the new region's workload
   directory; `_base.hcl` safety checks (below) catch misplacements at parse time.
6. **Apply** in dependency order (see [AGENTS.md](../../AGENTS.md#deployment-ordering--applydestroy-aws)).

## Safety validations

`_base.hcl` asserts at parse time (so a mis-copied directory refuses to plan):

- **Path-environment check** — the env segment of the directory path must match
  `env.hcl`'s `environment`.
- **Account mapping check** — the `account_id` in `env.hcl` must match the
  `environment_account_map` in `common.hcl`.

See [Environment Management](05-environment-management.md#isolation-boundaries).

## Multi-cloud

AWS is the only deployed cloud. An Azure/GCP `live/<cloud>/` tree would mirror this layout
(region/network/workload/unit), so the same scaffolding process and the eventual `platctl`
target apply unchanged when those clouds land.

## Next Steps

This is the final numbered design document. For day-to-day procedures see the runbooks
(`docs/runbooks/`) and the [Troubleshooting Guide](18-troubleshooting.md).
