# Runbooks Index

Step-by-step operational procedures for this platform, grouped by domain. Each entry
links to the runbook and summarizes what it covers. Architecture explainers (the *why*)
live in [`../architecture/`](../architecture/README.md); decisions in [`../adrs/`](../adrs/README.md).

## Cluster access & SSO

| Runbook | What it covers |
|---------|----------------|
| [EKS Cluster Access](eks-cluster-access.md) | kubectl/EKS API setup per role (PlatformAdmin, PlatformDeployer, DeveloperAccess-\<team\>) on the private clusters |
| [Tailscale VPN](tailscale-vpn.md) | Reaching the private EKS API and internal services over the tailnet via the subnet router |
| [SSO Troubleshooting](identity-sso-troubleshooting.md) | "Can't sign into ArgoCD/Backstage" or "logged in but no permissions" — master triage |
| [Manage People (joiner/mover/leaver)](manage-people.md) | Add/change/remove a person's workforce access end-to-end through the git-native People registry (`gitops/people/`) |
| [Keycloak Admin-Plane Break-Glass](keycloak-break-glass.md) | Recover admin control of Keycloak when passkey-MFA admin login is unavailable (ADR-087) |
| [Keycloak SSO](keycloak-sso.md) | **Optional / federation only** — wiring Identity Center as a SAML upstream when Keycloak is not the IdP of record |
| [Keycloak Upstream IdP](keycloak-upstream-idp.md) | Per-environment upstream IdP presets (SAML / OIDC) brokered behind the stable Keycloak seam (ADR-059) |
| [ArgoCD SSO](argocd-sso.md) | ⚠️ **Legacy** — the original embedded-Dex/SAML setup; ArgoCD now logs in against Keycloak OIDC directly |
| [Dex SSO Broker](dex-sso.md) | ⚠️ **Removed** — historical note; Dex was retired when Backstage moved to direct Keycloak OIDC |

## GitHub Apps & credentials

| Runbook | What it covers |
|---------|----------------|
| [ARC GitHub App](arc-github-app.md) | Credential for the self-hosted runner controller (ADR-065) — create the App, store the secret |
| [Backstage GitHub App](backstage-github-app.md) | Read-only App that lets Backstage discover `catalog-info.yaml` across the org |
| [Backstage Scaffolder GitHub App](backstage-scaffolder-github-app.md) | Write-capable App the scaffolder uses to open environment-provisioning PRs (ADR-062 §5) |
| [Backstage ArgoCD Plugin Token](backstage-argocd.md) | Read-only ArgoCD API token for the Backstage ArgoCD plugin (sync/health/history) |
| [GitHub Ownership App](github-ownership-app.md) | App the `github-teams` unit authenticates as to manage org Teams + repo ownership (ADR-072) |
| [Promote GitHub App](promote-github-app.md) | Write-capable App app CI uses to open release digest-bump PRs against the protected platform repo |
| [ArgoCD GitHub App](argocd-github-app.md) | Read-only App ArgoCD uses for repo-creds and the PR-preview `pullRequest` generator (ADR-032) |

## Supply chain

| Runbook | What it covers |
|---------|----------------|
| [App Supply-Chain Onboarding](app-supply-chain-onboarding.md) | Wire a service repo's CI to build, sign, attach SBOM + SLSA provenance, and pin by digest |
| [Supply-Chain Incidents](supply-chain-incidents.md) | Image verification failures at admission, Sigstore outage, identity rotation, break-glass |

## Delivery & releases

| Runbook | What it covers |
|---------|----------------|
| [Deploy App to Preprod](deploy-app-preprod.md) | Developer guide: repo structure, manifests, ECR push, ArgoCD sync to a preprod environment |
| [Promote a Release](promote-a-release.md) | Move a signed digest up the dev→test→uat→staging→prod ladder; approve a gated prod promotion |
| [Rollout & Metric-Gate Operations](rollout-and-gate-operations.md) | Platform-side progressive-delivery ops (ADR-056): inspect/pause/promote/abort rollouts and gates |
| [Debug ArgoCD Sync](debug-argocd-sync.md) | OutOfSync/Unknown, cross-account reachability, ApplicationSet PR-preview failures |
| [Debug Ingress & DNS](debug-ingress-and-dns.md) | App unreachable / TLS fails / hostname rejected — Cilium, external-dns, cert-manager, HTTPRoute, Kyverno |
| [gitops Gate Automerge](gitops-gate-automerge.md) | How registry PRs (environments/products/people/roles) validate and auto-merge without a human |

## Tenancy & environments

| Runbook | What it covers |
|---------|----------------|
| [Environment Onboarding](environment-onboarding.md) | Provision an environment via the registries + `XEnvironment` claim (Crossplane control plane) |
| [Environment Deprovisioning](environment-deprovisioning.md) | Safe two-step teardown: reversible decommission grace window, then gated hard-delete (ADR-062) |
| [Environment AWS Access (Pod Identity)](environment-aws-access-pod-identity.md) | How an environment Service gets least-privilege AWS access via EKS Pod Identity (ADR-041) |
| [Product Deprovisioning](product-deprovisioning.md) | Remove a whole Product and all its Environments cleanly, reversibly-until-the-last-step (ADR-062) |
| [New Cloud Resource (Self-Service)](new-resource.md) | Self-service provisioning of a cloud resource (S3/SQS/SNS/…) for an environment via the governed claim (ADR-073) |

## Observability

| Runbook | What it covers |
|---------|----------------|
| [Observability Access](observability-access.md) | Log into Grafana (Tailscale + creds), find dashboards, query metrics |
| [Observability Alerts](observability-alerts.md) | First-response notes for each curated platform alert (epic 102, P4) |
| [Instrumentation Verify](observability-instrumentation-verify.md) | Confirm zero-code Beyla RED metrics + traces appear with no app change (P7, ADR-077) |
| [Observability Spoke Onboarding](observability-spoke-onboarding.md) | Ship a workload cluster's metrics, logs, and traces to the central hub (hub-and-spoke, P10) |
| [Observability Troubleshooting](observability-troubleshooting.md) | Grafana/Prometheus/Alertmanager/Mimir diagnostics + the non-obvious deploy gotchas |

## AWS & org

| Runbook | What it covers |
|---------|----------------|
| [Add a New AWS Account](add-aws-account.md) | Create + wire a member account via the `organizations` module |
| [Modify SCPs](modify-scps.md) | Edit Service Control Policies (`organizations/scps.tf`) safely |
| [Incident: SCP Blocking](incident-scp-blocking.md) | Diagnose and unblock when an SCP denies a legitimate action |
| [Transit Gateway Operations](transit-gateway-operations.md) | Hub/spoke TGW: add spokes, verify connectivity, troubleshoot |
| [The Test Account](test-sandbox-account.md) | How the Terratest sandbox account (`157263244316`) is set up, accessed, and applied |

## Secrets

| Runbook | What it covers |
|---------|----------------|
| [Secret Rotation](secret-rotation.md) | Routine and compromised-secret rotation procedures |
| [Secrets Management Operations](secrets-management.md) | Day-2 ops for the Secrets Manager → ESO → cluster secret path |

## Cluster & platform ops

| Runbook | What it covers |
|---------|----------------|
| [Platform Rebuild from Scratch](platform-rebuild-from-scratch.md) | Full teardown + rebuild of the AWS platform via `platctl` |
| [Cluster Scale Down/Up](cluster-scale-down-up.md) | Park EKS node groups to zero overnight and restore them (cost), with the scale-up gotchas |
| [Karpenter Operations](karpenter-operations.md) | Day-2 node autoscaling: NodePool/EC2NodeClass tuning, consolidation/disruption, interruption handling, debugging stuck-Pending pods |
| [Upgrade Procedures](upgrade-procedures.md) | EKS, Cilium, Helm chart, and toolchain version upgrades |
| [Kyverno Break-Glass](kyverno-break-glass.md) | Temporarily exempt a workload from a policy + the Audit→Enforce flip procedure |
| [Platform-Agent Operations](agent-operations.md) | Day-2 ops for a live platform agent (`XAgent`): deploy, observe, suspend (kill-switch), reason about its autonomy envelope |
| [MCP Servers](mcp-servers.md) | The project-scoped read-only Grafana + AWS MCP servers for agent-assisted debugging |
