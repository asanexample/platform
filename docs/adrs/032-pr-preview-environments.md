# ADR-032: PR Preview Environments

**Date:** 2026-05-28

**Status:** Accepted

## Context

Development teams need a way to preview changes from pull requests before merging. A common
pattern is to deploy each open PR as an ephemeral environment with its own URL, allowing
reviewers to test the change in a running cluster without affecting the stable deployment.

The platform already uses ArgoCD for GitOps (ADR-021) with ApplicationSet controller enabled
(chart version 9.5.14). The ArgoCD ApplicationSet controller supports a Pull Request generator
that polls GitHub for open PRs and creates ephemeral Applications from a template.

The key challenges are:

1. **Label selector collision.** Kubernetes Deployments use label selectors to find their pods.
   If a preview Deployment and the stable Deployment share the same selector labels, their
   Services and ReplicaSets will cross-select each other's pods, causing traffic routing failures.

2. **HTTPRoute hostname collision.** Each preview needs a unique hostname. Gateway API HTTPRoute
   `backendRefs` are not automatically updated by kustomize `namePrefix`.

3. **OIDC trust for PR workflows.** GitHub Actions PR workflows use a different OIDC subject
   claim format (`repo:<org>/<repo>:pull_request`) than branch-based workflows
   (`repo:<org>/<repo>:ref:refs/heads/<branch>`). The OIDC trust policy must allow both.

4. **Image tagging.** ECR tag immutability (ADR-028) requires unique tags per image. PR previews
   use the PR's head commit SHA as the image tag.

### Alternatives Considered

**1. Manual preview deployments.** Developers create preview namespaces and deploy manually. This
is error-prone, creates namespace sprawl, and requires manual cleanup. Preview environments are
easily forgotten.

**2. Argo Rollouts with preview traffic splitting.** Use Argo Rollouts to split traffic to a
canary revision. This is designed for progressive delivery, not PR previews — it modifies the
stable deployment's rollout strategy and doesn't support multiple concurrent previews.

**3. External preview orchestrator (e.g., PullApprove, Uffizzi).** Third-party tools that
manage preview environments. These add operational dependencies, cost, and may not integrate
cleanly with the existing ArgoCD + Gateway API stack.

**4. ArgoCD ApplicationSet with PR generator (chosen).** Native ArgoCD capability. The
ApplicationSet controller polls GitHub for open PRs and creates/deletes Applications
automatically. Kustomize inline overrides handle resource naming, label isolation, and hostname
routing.

## Decision

Enable PR preview environments using ArgoCD ApplicationSet with the Pull Request generator.
Preview support is opt-in per app via the `preview = true` flag in `teams.hcl` (ADR-031).

### Architecture

```text
Developer opens PR
        |
        v
GitHub Actions (preview.yml)
  - OIDC auth (pull_request event)
  - Build + push image to ECR as team-<team>/<app>:<head-sha>
        |
        v
ArgoCD ApplicationSet (PR generator)
  - Polls GitHub API every 60s
  - Detects open PR
  - Creates ephemeral Application from template
        |
        v
Kustomize inline overrides
  - namePrefix: pr-<N>-
  - commonLabels: app.kubernetes.io/instance = pr-<N>
  - images: ECR image with head SHA tag
  - patches: HTTPRoute hostname rewrite
        |
        v
Kubernetes resources in team namespace
  - pr-<N>-<deployment>, pr-<N>-<service>, pr-<N>-<httproute>
  - Isolated by label selectors from stable deployment
        |
        v
Preview URL: <app>-pr-<N>.preprod.aws.refplat.org
```

### Label Selector Isolation

The critical design choice is using kustomize `commonLabels` on both the stable Application and
preview ApplicationSet template:

- **Stable Application:** `commonLabels: { "app.kubernetes.io/instance": "stable" }`
- **Preview Application:** `commonLabels: { "app.kubernetes.io/instance": "pr-<N>" }`

Kustomize `commonLabels` injects the label into Deployment `spec.selector.matchLabels`,
`spec.template.metadata.labels`, and Service `spec.selector`. This guarantees that the stable
Service only selects stable pods, and each preview Service only selects its own preview pods.

Without this, `namePrefix` renames resources but does NOT modify label selectors, causing
Services to cross-select pods from different deployments.

### HTTPRoute Patching

All preview kustomize transforms are injected **by the platform's ApplicationSet template** (in the
`argocd-apps` module), not by files in the app repo. The template sets `namePrefix = "pr-{{.number}}-"`,
`commonLabels`, an `images` override to the PR head SHA, and a hostname patch:

```yaml
# rendered into the ApplicationSet template by infra/modules/argocd-apps/
patches:
  - target: { kind: HTTPRoute }
    patch: |
      - op: replace
        path: /spec/hostnames/0
        value: <app>-pr-<N>.preprod.aws.refplat.org
```

> **Known limitation — HTTPRoute `backendRef` is not auto-rewritten.** Kustomize's built-in
> nameReference transformer does **not** know about Gateway API `HTTPRoute`, so `namePrefix` renames
> the `Service` (to `pr-<N>-<svc>`) and the `HTTPRoute` object but leaves the route's
> `spec.rules[].backendRefs[].name` pointing at the **un-prefixed** (stable) Service. An earlier
> design solved this with a per-app `name-reference.yaml` kustomize `configurations` file; that file
> is **not** present in the current app repos or module. Until backendRef rewriting is restored (via
> a module-side nameReference config, a JSON patch on `backendRefs`, or a templated app manifest),
> preview routing of the rewritten hostname to the **preview** Service should be verified per app —
> see the Risks section. Tracked in issue #155.

### OIDC Trust Policy Update

The `github_oidc` module adds a `github_events` variable that appends event-based subject claims
alongside branch-based claims:

```hcl
github_events = ["pull_request"]
```

This allows PR workflow OIDC tokens to authenticate and push images to ECR.

### Preview Lifecycle

| Event | Action |
|-------|--------|
| PR opened | ApplicationSet creates Application, ArgoCD syncs resources |
| PR updated (push) | GHA rebuilds image with new SHA, ArgoCD syncs updated manifests |
| PR closed/merged | ApplicationSet deletes Application, ArgoCD prunes all resources |

Cleanup is automatic — `prune = true` in the sync policy ensures all Kubernetes resources are
deleted when the Application is removed.

### GitHub Actions Workflows

Each app repo has two workflows:

- **`deploy.yml`** (push to main): Build, push to ECR, update manifests, commit. ArgoCD syncs
  the stable Application.
- **`preview.yml`** (pull_request): Build, push to ECR with PR head SHA tag. No manifest update
  needed — the ApplicationSet handles deployment via kustomize image override.

### Private Repository Access

Private app repos require two credential configurations:

1. **ArgoCD credential template** — ArgoCD needs read access to clone the repo for Application
   sync. Configure via `credential_templates` in the ArgoCD module:

   ```hcl
   credential_templates = {
     "github-asanexample" = {
       url      = "https://github.com/asanexample"
       password = "<github-pat-or-app-token>"
       username = "x-access-token"
     }
   }
   ```

   The template pattern-matches all repos under the `asanexample` org. Use a GitHub App installation
   token or a fine-grained PAT with `contents: read` scope. Store the token in AWS Secrets
   Manager and inject via External Secrets Operator.

2. **ApplicationSet GitHub token** — The PR generator needs GitHub API access to list open PRs.
   For private repos, unauthenticated access returns no results. Configure a token secret in the
   ArgoCD namespace:

   ```yaml
   apiVersion: v1
   kind: Secret
   metadata:
     name: github-token
     namespace: argocd
   stringData:
     token: <github-pat-or-app-token>
   ```

   Reference it in the ApplicationSet PR generator via `tokenRef`:

   ```hcl
   pullRequest = {
     github = {
       owner    = var.github_org
       repo     = regex("[^/]+$", each.value.repo_url)
       tokenRef = { secretName = "github-token", key = "token" }
     }
   }
   ```

   The same token can serve both purposes if it has `contents: read` scope. A GitHub App
   installation token is preferred over a PAT for auditability and fine-grained permissions.

### Kustomization Requirement

App repos must include a `kustomization.yaml` in their manifest directory listing all resources —
ArgoCD detects kustomize automatically when this file exists, and the ApplicationSet template's
overrides (`commonLabels`, `namePrefix`, image, hostname patch) only apply to a kustomize source:

```yaml
# k8s/preprod/kustomization.yaml (as in app-alpha)
resources:
  - serviceaccount.yaml
  - deployment.yaml
  - service.yaml
  - httproute.yaml
```

No `configurations:` / `name-reference.yaml` is present in the current app repos (see the HTTPRoute
Patching limitation above). The platform team owns the preview transform logic in the `argocd-apps`
module, so app repos stay minimal — they declare their resources and nothing preview-specific.

## Consequences

### Positive

- PR previews are fully automated — developers only need to open a PR.
- Cleanup is automatic — no orphaned preview resources.
- Preview environments share the team's existing namespace and resource quota, preventing
  namespace sprawl.
- The stable deployment is protected from preview interference via label selector isolation.
- No additional infrastructure (preview controllers, webhook handlers) — uses native ArgoCD.

### Negative

- Kustomize `commonLabels` on the stable Application means the stable deployment also gets an
  `app.kubernetes.io/instance: stable` label. This is semantically correct but is a change from
  the original raw manifests.
- The PR generator polls GitHub API every 60s. Private repos **require** a GitHub token for the
  PR generator (unauthenticated requests cannot see private repos). Public repos work without a
  token but are limited to 60 req/hr. A GitHub App token is recommended for both cases.
- Preview HTTPRoutes require wildcard DNS or per-PR DNS records. With external-dns and a wildcard
  CNAME, this is automatic. Without it, previews are only reachable via port-forward.

### Risks

- **Preview HTTPRoute may route to the stable Service.** As noted under HTTPRoute Patching,
  kustomize `namePrefix` does not rewrite an `HTTPRoute` `backendRef` (Gateway API CRD), and the
  `name-reference.yaml` mechanism that previously handled this is absent. A preview's rewritten
  hostname can therefore resolve to the stable Service/pods rather than the PR's preview pods,
  silently showing stable code under a preview URL. Until backendRef rewriting is restored, validate
  end-to-end preview routing before relying on it. Tracked in issue #155.
- **Fork PRs cannot push images.** GitHub blocks `id-token: write` on fork PRs by default, so
  forks cannot authenticate to ECR. The ApplicationSet will create an Application, but it will
  fail to sync because the image tag doesn't exist. This is safe (no resource creation) but may
  confuse external contributors. Mitigated by documenting in the app repo README.
- **PR image accumulation.** Each PR push creates a new ECR image tag. The ECR lifecycle policy
  (50 images, ADR-028) could evict production tags under high PR velocity. Mitigated by using
  separate ECR repos for preview images if volume warrants it.
- **Resource exhaustion from concurrent PRs.** Each preview creates ~2 pods (200m CPU, 256Mi).
  The default quota (4 CPU, 20 pods) limits to ~10 concurrent previews per team. Teams with high
  PR volume may need quota increases.
- **Per-team ECR push scope.** Push access uses one OIDC role per team
  (`github-actions-ecr-push-<team>`), each trusting only that team's repo and scoped to that team's
  `team-<team>/*` repositories (ADR-036). A compromised CI workflow for one team cannot push to
  another team's images.
