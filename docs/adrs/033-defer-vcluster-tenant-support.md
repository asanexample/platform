# ADR-033: Defer vCluster Tenant Support

**Date:** 2026-05-28

**Status:** Accepted

**Supersedes:** Partially supersedes ADR-027 (vCluster mode is deferred, not removed)

> **Amendment (2026-06-03, #174 / [ADR-046](046-back-stack-for-developer-self-service.md)):** The
> `infra/modules/tenant` module referenced below is **retired (deleted)** — tenant provisioning is now the
> Crossplane Tenant Composition. The vCluster decision is unchanged (all teams use namespace mode); but if
> vCluster isolation is ever revisited it would be delivered as a mode of the **Crossplane Composition**, not
> via the old `tenant` module's vCluster code path.

## Context

ADR-027 established a hybrid tenant isolation model with two modes: namespace (lightweight
isolation) and vCluster (full virtual control plane). The vCluster mode was designed to provide
CRD independence and stronger blast-radius containment for teams with complex workloads.

During implementation and validation of the vCluster tenant mode on the preprod cluster, we
discovered that **custom resource syncing** (specifically syncing HTTPRoute resources from the
virtual cluster to the host cluster) is gated behind vCluster's **Free tier**, which requires
deploying the vCluster Platform operator and connecting it to Loft's license server
(`admin.loft.sh`).

The open-source vCluster chart (what we deploy via Helm) does not support
`sync.toHost.customResources`. When configured, the vCluster pod crashes immediately:

```text
you are trying to use a vCluster pro feature 'Generic Sync' (vcp-distro-generic-sync)
that is not available in the open source vcluster
```

Without HTTPRoute sync, apps deployed inside a vCluster have no path to the shared Gateway API
Gateway. They would be unreachable from the internet — defeating the purpose of a preprod
environment where teams need publicly accessible preview URLs.

### Alternatives Considered

**1. Deploy vCluster Platform operator (Free tier).** The Free tier ($0) includes custom
resource sync but requires installing the vCluster Platform operator and maintaining a
connection to `admin.loft.sh` for license validation. This adds an external dependency on
Loft's infrastructure, a new operator to manage, and a different deployment model (Platform
CRDs vs standalone Helm). The operational complexity is disproportionate to the benefit for
2-3 teams in preprod.

**2. Host-side HTTPRoutes managed by Terraform.** vCluster OSS syncs Services from virtual
to host cluster by default (with deterministic naming: `<svc>-x-<ns>-x-<vcluster>`). We could
create HTTPRoutes on the host cluster via Terraform that point at these synced Services. This
works without Pro but means routing config lives in the platform repo, not the app repo — the
team loses self-service over their HTTPRoutes. It also makes PR preview environments
impractical for vCluster tenants.

**3. Namespace-only for all teams (chosen).** Use namespace isolation for all teams. This
provides a consistent model, full Gateway API routing, PR preview support, and no external
dependencies. The vCluster module remains in the codebase for future use if the licensing
landscape changes or if a use case arises where HTTPRoute sync is not needed.

## Decision

Defer vCluster tenant support. All teams use namespace isolation mode. The vCluster module
(`infra/modules/vcluster/`) is retained and upgraded to chart version 0.34.1 but is not
actively deployed. The tenant module's vCluster code path remains functional but has no
`custom_resource_sync` configured (since it requires Pro).

Conditions for revisiting:

- Loft moves custom resource sync to the open-source tier
- A team has a use case where vCluster isolation is needed without Gateway API routing
  (e.g., internal-only workloads reachable via `vcluster connect`)
- The team decides the vCluster Platform operator's operational overhead is acceptable

## Consequences

### Positive

- Single isolation model to document, monitor, and support
- All teams get consistent Gateway API routing and PR preview support
- No external dependency on Loft's license infrastructure
- Simpler onboarding — one kubectl access pattern, one namespace convention

### Negative

- Teams needing CRD independence or cluster-admin permissions cannot be accommodated without
  a separate EKS cluster or accepting the vCluster Platform dependency
- The vCluster module is maintained code that is not exercised in production, which may
  drift from the chart's actual behavior over time

### Risks

- If a team with legitimate vCluster requirements is onboarded, the platform team will need
  to either accept the Platform operator dependency or provision a separate EKS cluster,
  both of which have longer lead times than a simple `teams.hcl` mode change
