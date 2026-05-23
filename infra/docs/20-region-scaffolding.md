# Region Scaffolding

> **TODO**: This document needs to be written when a region scaffolding tool is implemented. Topics to cover:
>
> - Script or Makefile target to scaffold a new region directory
> - Files that must be created: `region.hcl`, `network.hcl`, workload directories with `workload.hcl`
> - How `_base.hcl` inheritance works for new regions (see [Configuration Hierarchy](../../docs/architecture/config-hierarchy.md))
> - CIDR allocation for the new region (see [06-cidr-allocation.md](./06-cidr-allocation.md))
> - Safety validations (path-environment check, subscription mapping check)
> - Multi-cloud scaffolding (same pattern across AWS, Azure, GCP)
>
> Currently, new regions are scaffolded manually by copying an existing region directory and updating `region.hcl` and `network.hcl`.
