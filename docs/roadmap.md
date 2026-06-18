# Platform Roadmap

The single forward-looking map of the platform: **everything shipped and everything planned**, organized by **functional area** (the *what*) and **horizon** (the *when*). This is the navigable picture; [GitHub Issues](https://github.com/asanexample/platform/issues) remains the system of record for live status and detail. "Complete picture" means every capability and area is represented — not every ticket.

**How to read it:** the **Forward roadmap** (Now → Next → Later) is what we steer by; **Shipped capabilities** is the backfilled map of what already exists (one card per capability, not per commit). Items link to their tracking issue where one exists.

---

## Forward roadmap

### Now

_Actively in flight or next-up._

**GitOps & Delivery**

- [#377](https://github.com/asanexample/platform/issues/377) P2 (ADR-067): Promotion — promote-by-digest, auto ≤ staging, gated prod

**Developer Portal**

- [#553](https://github.com/asanexample/platform/issues/553) ADR-073 Phase A.2: Backstage New Resource form + live resource status
- [#370](https://github.com/asanexample/platform/issues/370) P1 (ADR-067): New Service + multi-env starter + Product-as-System + product-scoped identity

**Environment & Resource Control Plane**

- [#555](https://github.com/asanexample/platform/issues/555) Epic: self-service cloud resources — the resource paved road (ADR-073)

### Next

_Queued — the near-term build order._

**Identity & Access**

- [#361](https://github.com/asanexample/platform/issues/361) P4 (ADR-068): Product-scoped & cross-team access model
- [#362](https://github.com/asanexample/platform/issues/362) P4.1 (ADR-068): AccessGrant CRD + cluster projection
- [#363](https://github.com/asanexample/platform/issues/363) P4.2 (ADR-068): Access-model-as-code — Product roles in Keycloak
- [#364](https://github.com/asanexample/platform/issues/364) P4.3 (ADR-068): OIDC-native developer cluster auth (EKS OIDC IdP)
- [#365](https://github.com/asanexample/platform/issues/365) P4.4 (ADR-068): Fan-out — ArgoCD RBAC + Backstage permissions from product roles
- [#366](https://github.com/asanexample/platform/issues/366) P4.5 (ADR-068): release-approver + gated prod promotion
- [#367](https://github.com/asanexample/platform/issues/367) P4.6 (ADR-068): team-admin governance + grant lifecycle (request/TTL/re-attest)
- [#368](https://github.com/asanexample/platform/issues/368) P4.7 (ADR-068): Two-plane grant enforcement (access-grant-gate CI + Kyverno)

**GitOps & Delivery**

- [#500](https://github.com/asanexample/platform/issues/500) P2.4 (ADR-056): progressive delivery for prod — Argo Rollouts
- [#502](https://github.com/asanexample/platform/issues/502) P2.6: multi-service Request Promotion template
- **Immutable release + environment-binding promotion** — Net-new delta. Builds ON the shipped Release-CRD digest promotion (ADR-071) + release-keyed ApplicationSet (#495, done) + promotion ladder (#377). New = an immutable release as the artifact and a binding as the promotion/rollback primitive (rollback = re-point the binding).

**Developer Portal**

- [#554](https://github.com/asanexample/platform/issues/554) ADR-073 Phase B: conversational resource agent
- [#285](https://github.com/asanexample/platform/issues/285) BACK P5: provisioning visibility — polished experience (ADR-064)
- [#356](https://github.com/asanexample/platform/issues/356) Backstage: unified "in-flight" view of teams/tenants (open requests + provisioning-not-Ready)
- [#178](https://github.com/asanexample/platform/issues/178) Epic: Developer self-service via the BACK stack (ADR-046)
- [#386](https://github.com/asanexample/platform/issues/386) P1 prereq: create asanexample/golden-path-starters + scaffolder read access
- [#372](https://github.com/asanexample/platform/issues/372) P1.2/L3a (ADR-067): New Product scaffolder template (repo-on-demand, language picker)
- [#373](https://github.com/asanexample/platform/issues/373) P1.3 (ADR-067): catalog projection — Product=System, Service=Component, custom kind Environment
- [#374](https://github.com/asanexample/platform/issues/374) P1.4 (ADR-067): Product-scoped image identity (ECR + cosign + verify-images)
- [#375](https://github.com/asanexample/platform/issues/375) P1.5 (ADR-067): Platform-injection of namespace + hostname (ns-agnostic manifests)
- [#376](https://github.com/asanexample/platform/issues/376) P1.6 (ADR-067): Multi-env starter (base/overlays + stage-picker; fix app-bravo hardcoded namespace)
- **Golden paths as first-class API objects** — Net-new delta. Today paved roads are scaffolder cookiecutter templates (shipped, ADR-062). New = model golden paths as queryable, composable platform API objects the platform reasons about. Relates #358 (add service to existing repo).

**Environment & Resource Control Plane**

- [#391](https://github.com/asanexample/platform/issues/391) Secrets paved-road: tenant app config & secrets (ADR-070)

**Cost & FinOps**

- **Cost guardrails — aggregate budgets + FinOps visibility** — Forward half of Cost & FinOps. Aggregate per-team budgets/caps (the quota-cap dial seam left by Phase 3), cost dashboards/FinOps visibility, anomaly alerts.

### Later

_On the map, not yet scheduled (incl. per-area backlogs)._

**Network & Connectivity**

- **Network hardening backlog** — Rollup -> filter label:area/network. Includes #162 WireGuard pod encryption, #163 node subnet sizing, #166 Kyverno HA hostNetwork, #206 subnet-router after scale-up.

**Kubernetes & Ingress**

- **Autoscaling** — Workload + cluster autoscaling as a paved-road capability (HPA/VPA/Karpenter-class), governed and surfaced through the platform abstractions.

**Identity & Access**

- **East-west zero-trust mTLS / service identity** — Decided (ADR-057), not yet built. Service identity + east-west mTLS zero-trust between workloads.

**Governance & Supply-chain**

- **Kyverno policy backlog** — Rollup -> filter label:area/policy. Includes #77 CEL ValidatingPolicy, #78 PolicyException governance, #79 HIPAA/PCI packs, #80 kyverno-json, #81 multi-cluster distribution, #82 nodeSelector validation, #93 PolicyReport observability.
- **Security & hardening backlog** — Rollup -> filter label:security. Includes #59 _v1 rename, #70 prod least-privilege, #111 ArgoCD GitHub App, #118 customer KMS CMKs, #129 SCA/AppSec, #132 CSPM, #149 Falco, #152 state-bootstrap S3, #196 Backstage ns hardening, #213 token rotation, #242 EBS orphans, #243 chart-repo resilience, #273 CoreDNS.

**Developer Portal**

- [#177](https://github.com/asanexample/platform/issues/177) BACK stack P6: Backstage plugins (ArgoCD, Crossplane, Kyverno, Grafana)
- [#200](https://github.com/asanexample/platform/issues/200) Represent the Terraform/Terragrunt platform infra in the Backstage catalog
- **Higher-altitude developer abstraction** — Net-new. Developers declare intent (e.g. an internal HTTP endpoint); the platform synthesizes HTTPRoute + NetworkPolicy + policy-compliant wiring, vs near-raw manifests. Relates #375 (platform-injection).

**Environment & Resource Control Plane**

- [#105](https://github.com/asanexample/platform/issues/105) Developer environments (ephemeral dev sandboxes / devcontainers)
- [#378](https://github.com/asanexample/platform/issues/378) P3 (ADR-067): Customers + graduated isolation
- [#379](https://github.com/asanexample/platform/issues/379) P5 (ADR-067): Placement / multi-cluster (HA/DR) + Service→Resource dependencies
- **Multi-cloud** — Extend the cloud-resource control plane + governance beyond AWS (Azure/GCP) behind the same governed-claim + derived-IAM model. Currently AWS-only.

**Observability**

- [#102](https://github.com/asanexample/platform/issues/102) Observability stack (epic) — metrics, logs, traces, profiles, cost

**Platform Tooling & Ops**

- **Resilience & BC / DR posture** — Decided (ADR-054), partial. Teardown→rebuild validated (done); broader DR/business-continuity posture outstanding. Overlaps #379 placement.
- **platctl & CI backlog** — Rollup. Includes #299 platctl CI+coverage, #305 Terragrunt post-merge converge, #346 teams CI TG_DEPENDENCY_FETCH, #348 teams CI sts:TagSession.

---

## Shipped capabilities

_The capability map of what the platform does today. Each bullet ≈ one ADR cluster or epic._

### Cloud Foundation

- **Multi-account AWS Org + SCPs + OU hierarchy** — Shipped. AWS Organizations, Service Control Policies, OU hierarchy (ADR-003/004/005). Includes CloudTrail secrets audit logging (ADR-037).
- **OpenTofu/Terragrunt monorepo + S3 state + IAM role model** — Shipped. Terragrunt hierarchy, S3 state bootstrap, PlatformAdmin/Deployer role model. ADR-001/002/006/007/016.

### Network & Connectivity

- **Private cluster access: Tailscale + SSM bastion** — Shipped. Tailscale subnet routers advertise VPC CIDR + split-DNS; SSM Session Manager bastion. ADR-011/020.
- **VPC/CIDR + DNS + Transit Gateway + cross-VPC DNS** — Shipped. CIDR strategy, Route53/Cloudflare delegation, TGW hub-spoke, cross-VPC DNS resolution. ADR-015/022/034/035.

### Kubernetes & Ingress

- **Cilium CNI — kube-proxy replacement, netpol, Gateway API** — Shipped. Cilium 1.19, kubeProxyReplacement, network policy, Cilium Gateway API. ADR-008/017.
- **Private EKS (BYOCNI) + node groups + managed addons** — Shipped. Private-only API EKS, BYOCNI ordering, separated node groups + coredns addon. ADR-009/010/023.
- **Shared Gateway + cert-manager + external-dns** — Shipped. Foundational shared Gateway + ClusterIssuer, Let's Encrypt DNS-01, external-dns. ADR-029/030/059/060/061.

### Identity & Access

- **EKS Pod Identity for workload AWS access** — Shipped. Pod Identity associations replace IRSA annotations for environment workloads. ADR-041/047.
- **Keycloak IdP + OIDC consolidation (Dex/oauth2-proxy retired)** — Shipped. Keycloak as IdP-of-record, OIDC for ArgoCD+Backstage, retired Dex+oauth2-proxy. ADR-052/053/059.
- **Per-team developer RBAC + platform-engineer access model** — Shipped. DeveloperAccess-<team> namespace-scoped RBAC; PlatformAdmin operate-not-author. ADR-039/040.

### Governance & Supply-chain

- **Compliance-tier model + SOPS-encrypted config secrets** — Shipped. standard/pci/hipaa tiers drive config; SOPS/KMS committed secrets. ADR-013/055/066.
- **Keyless cosign signing + SBOM + SLSA L3 provenance** — Shipped. cosign keyless signatures, CycloneDX SBOM, SLSA Build L3 provenance, verify at admission. ADR-042/050.
- **Kyverno admission engine + Audit→Enforce rollout** — Shipped. Kyverno HA engine + ClusterPolicies, phased Audit→Enforce on preprod+platform. ADR-014.
- **Per-product image scoping + supply-chain split** — Shipped. Kyverno restrict-images per Product registry; platform-owned cosign verify vs product-owned restrict (ADR-067). Includes ECR cross-account container registry (ADR-028).
- **Secrets management: External Secrets Operator + Secrets Manager** — Shipped. ESO + ClusterSecretStore sync from AWS Secrets Manager/SSM; secret naming convention + cross-account secret isolation. ADR-019/024/025/026.

### GitOps & Delivery

- **ApplicationSets + PR preview environments** — Shipped. ApplicationSet generators; PR-preview ephemeral deployments. ADR-032.
- **ArgoCD GitOps + per-team AppProjects/RBAC** — Shipped. ArgoCD delivery engine, per-team AppProjects, SSO RBAC. ADR-021.
- **Multi-stage promotion: auto ≤ staging + gated prod** — Shipped (P2). Promote-by-digest, auto-promote reconciler ≤ staging, gated prod. ADR-067 P2 / #377.
- **Release-CRD digest promotion + Product-registry source-of-truth** — Shipped. Image-digest promotion via control plane (protected-main); Product registry + Environment claims drive delivery. ADR-069/071.

### Developer Portal

- **Backstage portal + catalog + direct Keycloak OIDC** — Shipped. Backstage at backstage.aws.refplat.org, catalog, direct Keycloak OIDC signin. ADR-051.
- **Catalog projection + live K8s/ArgoCD/MR status + RBAC** — Shipped. v3 projection (Product=System/Service=Component/Environment), live K8s+ArgoCD plugins + namespaced-MR status (#574), Keycloak-group RBAC (#197). ADR-064.
- **Scaffolder: New Product/Team/Resource templates + multi-language starters** — Shipped. Self-service scaffolder templates (Product/Team/Resource/deprovision) + Go/Node/Python/Java/Rust/Rails starters. ADR-062.

### Environment & Resource Control Plane

- **Crossplane Environment API + v3 domain-model cutover** — Shipped. XEnvironment XRD+Composition; v3 Team/Product/Service/Environment cutover. ADR-048/067.
- **Live resource status — namespaced MRs in catalog** — Shipped. Tenant resource plane on namespaced aws.m.upbound.io MRs, live status in Backstage. #574.
- **Safe environment/product deprovisioning lifecycle** — Shipped. Reversible decommissioning suspend; admin-gated hard-delete; ECR orphaned. ADR-062.
- **Self-service cloud resources: S3/SQS/SNS/DynamoDB + derived IAM** — Shipped. Governed-claim resources with curated Compositions + DERIVED least-privilege IAM. ADR-073.

### Domain Model & Ownership

- **App-repo naming + GitHub org-Team ownership** — Shipped. Dropped app- prefix; GitHub org Teams own app repos, registry-derived. ADR-072 (epic #532).
- **Team→Product→Service→Environment model + git-native Team registry** — Shipped. ADR-067 domain model; git-native Team CR + Product/Environment registries as source of truth. ADR-063/067.

### CI & Build

- **GitHub OIDC federation for CI** — Shipped. Keyless GitHub Actions OIDC to AWS for CI/CD. ADR-036.
- **Self-hosted ARC runners + shared trusted-ci build-sign** — Shipped. Actions Runner Controller in-VPC CI; shared trusted-ci build-sign/SLSA reusable workflows. ADR-050/065.

### Observability

- **Falco runtime threat detection (preprod)** — Shipped. Falco eBPF runtime threat detection on preprod. ADR-045.
- **Prometheus/Grafana stack + Mimir durable metrics** — Shipped (P1+P2). kube-prometheus-stack + Grafana; Mimir S3-backed durable metrics via remote-write. ADR-043/044.

### Cost & FinOps

- **Per-environment ResourceQuota + cost-allocation tags** — Shipped baseline. Per-environment ResourceQuota; Team/Product/Stage cost-allocation tags on resources.

### Platform Tooling & Ops

- **Validated teardown→rebuild-from-scratch** — Shipped. Repeatable full teardown+rebuild (58/58) validated; runbook + platctl automation.
- **platctl CLI — bootstrap/teardown/validate** — Shipped. platctl: bootstrap, teardown, lockdown/unlock, validate, kubeconfig; DAG-aware. ADR-038.

---

## How this roadmap is maintained

- **Roadmap-driven:** new work is picked from **Now / Next** here; each item links to its tracking issue.
- **When something ships:** move it out of Forward and add a one-line capability bullet under **Shipped** (capability granularity — not one bullet per PR), and close its issue.
- **When something new is planned:** add it under the right Area + Horizon, with an issue link if it's decomposed.
- **Source of truth split:** this doc = the narrative map; GitHub Issues = live tracking/detail. Keep them in step.
- **Granularity (the "diamond"):** coarse for shipped (capabilities), fine for Now/Next (real issues), coarse for Later (themes + per-area backlogs).

