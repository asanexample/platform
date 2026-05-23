# ADR-021: ArgoCD for GitOps Delivery

**Date:** 2026-05-23

**Status:** Accepted

## Context

The platform needs a deployment mechanism for Kubernetes workloads — both platform services
(cert-manager, external-dns, monitoring) and tenant applications. The two dominant models are:

1. **Push-based deployment.** CI pipelines build artifacts and push them to the cluster via
   `kubectl apply` or `helm upgrade`. The pipeline has cluster credentials and drives the
   deployment directly.

2. **Pull-based deployment (GitOps).** An in-cluster agent watches a Git repository and
   continuously reconciles the cluster state with the desired state declared in Git. The cluster
   pulls its own configuration rather than having it pushed.

The platform's EKS cluster has a private-only API endpoint (ADR-010), which makes push-based
deployment from external CI systems difficult — GitHub Actions runners cannot reach the API
without VPC connectivity. GitOps sidesteps this problem entirely: the agent runs inside the
cluster and pulls from Git, so it has native access to the API server.

### Alternatives Considered

**1. Push-based CI/CD (GitHub Actions → kubectl/helm).** Straightforward: build, test, deploy in
a pipeline. Works well for simple setups. However, with a private API endpoint, GitHub Actions
runners need VPC access (self-hosted runners on EKS, or tunnel through Tailscale). Push-based
deployments also have no continuous reconciliation — if someone manually modifies a resource,
the drift persists until the next pipeline run.

**2. Flux.** CNCF GitOps project. Uses a set of controllers (source-controller, kustomize-
controller, helm-controller) to reconcile Git repositories with cluster state. Flux is lightweight,
composable, and integrates well with Kustomize. However, Flux has no built-in UI — visibility
into sync status, diff previews, and rollback history requires additional tooling or CLI
commands. For a platform team that needs to observe deployment status across multiple workloads,
the lack of a UI is a significant operational gap.

**3. ArgoCD (chosen).** CNCF graduated GitOps project. Provides continuous reconciliation with a
comprehensive web UI showing sync status, resource health, live manifests, and diff views.
Supports Helm, Kustomize, and plain YAML. The App-of-Apps pattern enables declarative management
of multiple applications from a single root application. ArgoCD is the most widely adopted GitOps
tool in the Kubernetes ecosystem.

## Decision

Deploy ArgoCD on all Kubernetes clusters for GitOps-based workload delivery. The module
(`infra/modules/argocd/`) installs ArgoCD via Helm, and the `argocd-bootstrap` module provides
the App-of-Apps pattern for declarative application management.

### Deployment Architecture

ArgoCD is deployed as a Terragrunt unit (`argocd`) that depends on EKS and node-groups. It
installs the ArgoCD Helm chart with IRSA (ADR-018) for ECR image access.

The `argocd-bootstrap` module creates ArgoCD `Application` resources that define the initial set
of applications to manage. This enables a bootstrap pattern where the first `terragrunt apply`
sets up ArgoCD and its initial applications, and subsequent changes to those applications are
managed via Git.

### SSO Integration

ArgoCD authenticates users via Dex and SAML, integrated with AWS Identity Center (ADR-012). Group
claims from SAML drive RBAC within ArgoCD.

### IRSA for ECR Access

ArgoCD's service accounts (server, repo-server, application-controller) are annotated with IRSA
roles that grant ECR read-only access. This allows ArgoCD to pull container images and Helm charts
from the platform's ECR repositories without storing registry credentials.

### Helm Chart Version

ArgoCD chart version is centrally pinned in `_versions.hcl` (currently 9.5.14).

### Module Design

The ArgoCD module is cloud-agnostic. Cloud-specific configuration (IRSA, SSO) is injected via
variables from the live unit. The module accepts:

- `oidc_provider_arn/url` for IRSA configuration
- `dex_enabled` and `argocd_cm_extra` for SSO configuration
- `helm_chart_version` from centralized version pins

This design allows the same module to be used on Azure (AKS) with Azure AD OIDC instead of SAML,
by changing only the live unit's inputs.

## Consequences

**Positive:**

- GitOps reconciliation — cluster state continuously matches Git. Manual drift is detected and
  corrected automatically.
- Web UI provides visibility into sync status, resource health, and deployment history without
  CLI access
- Private API endpoint is not a barrier — ArgoCD runs inside the cluster and has native API access
- App-of-Apps pattern enables declarative management of the entire application portfolio
- IRSA integration eliminates stored credentials for ECR access
- Cloud-agnostic module supports multi-cloud deployment

**Negative:**

- ArgoCD is a complex system — server, repo-server, application-controller, Redis, and
  optionally Dex. More components to monitor and troubleshoot than Flux's controller-per-concern
  model.
- ArgoCD's Helm chart has many configuration options and frequent releases — upgrades require
  review of breaking changes
- The App-of-Apps pattern creates a dependency tree where the root application must be healthy
  for child applications to sync. A broken root app blocks all deployments.
- ArgoCD's resource requirements (especially repo-server for large repositories) are higher than
  Flux's minimal footprint

**Risks:**

- If ArgoCD is down, applications continue running (they're already deployed), but new
  deployments and drift correction stop. Mitigated by monitoring ArgoCD health and configuring
  alerts on sync failures.
- ArgoCD has cluster-admin-level access to deploy any resource. A compromised ArgoCD instance
  could modify or delete any cluster resource. Mitigated by RBAC, network policies, and
  restricting ArgoCD's project configurations to approved namespaces and resource types.
