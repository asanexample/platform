# ADR-031: Multi-App Tenant Model

**Date:** 2026-05-28

**Status:** Accepted

## Context

ADR-027 established a hybrid tenant isolation model where each team declares its isolation mode
(`namespace` or `vcluster`) in `teams.hcl`. The initial data model mapped one application per team:

```hcl
alpha = {
  mode      = "namespace"
  repo_url  = "https://github.com/asanexample/app-alpha"
  repo_path = "k8s/preprod"
}
```

This one-to-one mapping breaks down for two common scenarios:

1. **Multi-repo teams.** A team owns multiple microservices, each in its own GitHub repository.
   Under the original model, the team would need a separate `teams.hcl` entry per service, which
   conflates team identity (isolation boundary) with application identity (deployment unit).

2. **Monorepo teams.** A team has a single repository containing multiple services, each in a
   different subdirectory. The original model's single `repo_path` cannot express this.

Both scenarios require decoupling the team definition (isolation mode, namespace, resource quotas)
from the application definition (repository, path, branch, preview enablement).

### Alternatives Considered

**1. One teams.hcl entry per service.** Create `alpha-api`, `alpha-worker`, etc. as separate team
entries. This gives each service its own namespace, quota, and EKS access entry. However, services
that belong to the same team would be isolated from each other by NetworkPolicy, defeating the
purpose of shared-team namespaces. It also inflates the DeveloperAccess namespace list and makes
resource quota management per-team impossible (quotas are per-namespace).

**2. Flatten apps into a separate top-level map.** Define `apps.hcl` alongside `teams.hcl` with
cross-references. This separates concerns cleanly but doubles the configuration surface and
introduces referential integrity issues (an app referencing a team that doesn't exist).

**3. Nested apps map within each team (chosen).** Each team entry contains an `apps` map. The team
definition controls isolation; each app entry controls the deployment source. This preserves the
single-file, single-source-of-truth property of `teams.hcl` while supporting arbitrary apps per
team.

## Decision

Restructure `teams.hcl` to nest applications within each team:

```hcl
locals {
  teams = {
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
  }
}
```

Each app entry supports:

| Field | Type | Default | Purpose |
|-------|------|---------|---------|
| `repo_url` | string | required | Git repository URL |
| `repo_path` | string | `k8s/preprod` | Path within the repo to K8s manifests |
| `repo_branch` | string | `main` | Branch to track for the main Application |
| `preview` | bool | `false` | Enable PR preview environments (ADR-032) |

### ECR Naming Convention

ECR repositories follow `team-<team>/<app>` naming (e.g., `team-alpha/demo`). This provides
clear provenance and avoids collisions between teams.

### ArgoCD Resource Mapping

The `argocd-apps` module flattens the nested apps for iteration:

- **AppProject** — 1 per team. `sourceRepos` includes all repos across the team's apps.
- **Application** — 1 per app. Named `<team>-<app>` (e.g., `alpha-demo`). Deploys into the
  team's namespace with kustomize `commonLabels` for selector isolation.
- **ApplicationSet** — 1 per preview-enabled app (see ADR-032).

All apps within a team share the same namespace and resource quota. The team boundary remains the
isolation unit; apps are deployment units within that boundary.

### Downstream Consumers

Units that read `teams.hcl` are updated to handle the nested structure:

| Unit | Change |
|------|--------|
| `tenants/` | No change — reads `mode` only, apps are irrelevant |
| `eks/` | No change — reads team keys for namespace list only |
| `argocd-apps/` | Rewritten — iterates nested apps for Applications and ApplicationSets |
| `ecr/` | Repo names updated to `team-<team>/<app>` convention |
| `github-oidc/` | No structural change — repo list still flat |

## Consequences

### Positive

- Teams can own multiple applications without duplicating team-level configuration.
- Monorepo and multi-repo teams use the same model — only `repo_url` and `repo_path` differ.
- ECR naming convention (`team-<team>/<app>`) provides clear image provenance.
- Adding an app to an existing team is a 5-line change in `teams.hcl`.
- Resource quotas remain team-scoped, preventing quota fragmentation across services.

### Negative

- The `tenants` variable type in `argocd-apps` is more complex (nested object with map of objects).
- Teams with very different resource profiles across apps cannot set per-app quotas — the quota
  applies to the entire namespace.

### Risks

- A team with many apps in one namespace could hit the namespace-level ResourceQuota with normal
  operations. Mitigated by monitoring quota usage and adjusting per-team overrides.
- The flattened app key (`<team>-<app>`) must be unique across all teams. Collisions are unlikely
  given the prefix structure but would cause a Terraform error at plan time.
