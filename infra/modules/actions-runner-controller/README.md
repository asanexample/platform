# actions-runner-controller

Deploys [Actions Runner Controller (ARC)](https://github.com/actions/actions-runner-controller) in
**Autoscaling Runner Scale Sets** mode onto the platform EKS cluster, giving CI an **in-VPC runner pool**
that can reach the private EKS API — which GitHub-hosted runners can't (ADR-065 / #323).

Delivered by Terragrunt `helm_release` like every other platform add-on (ArgoCD is reserved for tenant
workloads). Because ARC is what lets CI manage the cluster, its unit is applied **locally / via `platctl`**
(break-glass) — it can't bootstrap itself.

## What it creates

- Namespaces `arc-systems` (controller) and `arc-runners` (runner pods).
- The **gha-runner-scale-set-controller** Helm release.
- A repo-scoped **gha-runner-scale-set** (`runs-on: platform-infra`), running the custom
  `platform/gha-runner` toolchain image, scale-to-zero, no docker-in-docker.
- An **ExternalSecret** projecting the GitHub App creds (Secrets Manager → `arc-github-app`).

## Scope (this module)

Gets runners **registered and idle**. The privileged AWS-creds path — runner Pod Identity → assume
`PlatformDeployer`, the `PlatformDeployer` trust amendment, and the `terragrunt plan` smoke proof — lands
separately so the high-privilege bits review on their own.

## Prerequisites

- ESO operator (`external-secrets`) + the `aws-secrets-manager` ClusterSecretStore (`secret-stores`).
- The GitHub App + its Secrets Manager secret — see `docs/runbooks/arc-github-app.md`.
- The `platform/gha-runner` image built + pushed (`gha-runner-image.yml`).

## Key inputs

| Input | Purpose |
|-------|---------|
| `cluster_name` | EKS cluster (from the `eks` unit) |
| `runner_image` | Full ECR ref of the toolchain image; bump the tag + re-apply to roll |
| `controller_chart_version` / `runner_set_chart_version` | ARC chart pins (lockstep) |
| `runner_scale_set_name` | The `runs-on:` label (default `platform-infra`) |
| `min_runners` / `max_runners` | Autoscale bounds (default 0 / 3) |
| `github_app_secret_name` | Secrets Manager key (JSON: appId, installationId, privateKey) |
