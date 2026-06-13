# Platform Requirements

## 1. Architecture

1. Use OpenTofu with Terragrunt for infrastructure management across AWS, Azure,
   and GCP (ADR-016)
2. Cloud-aware state management: S3 with DynamoDB locking for AWS, Azure Blob
   Storage for Azure — root `root.hcl` routes automatically based on directory
   path (ADR-002)
3. State stored in management account (<MGMT_ACCOUNT_ID>) with a dedicated
   `TerraformStateAccess` IAM role — isolation by key path
   (`{env}/{region}/{workload}/{unit}/terraform.tfstate`), not by bucket
   (ADR-006)
4. S3 state bucket with versioning enabled for rollback; DynamoDB table for
   concurrent apply locking
5. Monorepo structure with three layers: reusable modules (`infra/modules/`),
   cloud-specific modules (`infra/modules/aws/`, `azure/`, etc.), and live
   environment configs (`infra/live/{cloud}/{env}/{region}/{workload}/`)
6. Seven-layer Terragrunt config hierarchy: `root.hcl` → `_base.hcl` →
   `env.hcl` → `region.hcl` → `network.hcl` → `workload.hcl` → `common.hcl`
   → unit `terragrunt.hcl` — environment, region, account ID, CIDR, tags, and
   provider config are inherited with explicit merge precedence (ADR-001)
7. Safety assertions in `_base.hcl`: directory path must match `env.hcl`
   environment name, and caller account ID must match the
   `environment_account_map` in `common.hcl` — prevents accidental cross-account
   applies
8. Support multiple environments per cloud: management, platform, preprod, prod
   (AWS); dev, ops (Azure); ops (GCP)
9. Multi-account AWS organization with purpose-built IAM roles for cross-account
   access (ADR-004, ADR-007)
10. Hierarchical CIDR allocation: /14 per cloud (AWS `10.100.0.0/14`, Azure
   `10.104.0.0/14`, GCP `10.108.0.0/14`), /16 per environment within each
   cloud (ADR-015)
11. Kubernetes overlay CIDRs shared across all clusters: pod CIDR
    `10.240.0.0/16`, service CIDR `10.241.0.0/16`, DNS service IP
    `10.241.0.10` (ADR-015)
12. Network architecture with 6 subnet tiers per region across 3 AZs: kubernetes
    (/26), endpoints (/26), firewall (/26), services (/27), public (/28),
    transit (/28)
13. Three network topology modes: private (NAT egress via IGW), public (direct
    IGW), airgapped (no internet connectivity) — controlled by boolean flags on
    the networking module (ADR-015)
14. VPC endpoints for S3 (gateway, always created), Secrets Manager, SSM, STS,
    and KMS (interface, configurable) to reduce NAT costs and enable airgapped
    operation
15. Universal `create` toggle on every resource-creating module for selective
    deployment without config removal
16. All Terragrunt dependency blocks include `mock_outputs` so destroy works even
    when upstream dependencies are already gone
17. Deployment ordering enforced by Terragrunt DAG: `platctl bootstrap` resolves
    the full dependency graph automatically (ADR-038)

## 2. Kubernetes Platform

### 2.1 EKS Configuration

1. EKS with BYOCNI (`bootstrap_self_managed_addons = false`) — no default CNI,
   kube-proxy, or CoreDNS installed at cluster creation (ADR-009)
2. EKS component separation into four ordered units: eks → cilium → node-groups
   → eks-addons, because Cilium must be running before nodes can join and addon
   pods need CNI + nodes to schedule (ADR-009)
3. EKS access entries model (`API_AND_CONFIG_MAP` authentication mode) replacing
   aws-auth ConfigMap for IAM-to-Kubernetes RBAC mapping — supports cluster and
   namespace scope types
4. KMS customer-managed key per cluster for Kubernetes secrets encryption
   (envelope encryption of etcd), with automatic key rotation enabled
5. OIDC provider per cluster for IRSA — client ID `sts.amazonaws.com`,
   thumbprint extracted from cluster identity
6. Control plane logging: api, audit, authenticator, controllerManager, scheduler
7. EKS managed add-ons (CoreDNS, kube-proxy, EBS CSI driver) in a separate
   `eks-addons` unit that depends on cilium + node-groups, since addon pods need
   the CNI to schedule (ADR-009)
8. Two-phase EKS endpoint access: deployed with `endpoint_public_access = true`
   during bootstrap so Terragrunt can reach the API, then locked down to
   private-only after Tailscale is operational (ADR-010, ADR-038)

### 2.2 Node Groups

1. Managed node groups with configurable instance types, capacity type
   (ON_DEMAND/SPOT), and AMI type (default: AL2023_x86_64_STANDARD)
2. Node IAM role with AmazonEKSWorkerNodePolicy,
   AmazonEC2ContainerRegistryReadOnly, AmazonSSMManagedInstanceCore, and
   AmazonEKS_CNI_Policy
3. Rolling update strategy with configurable `max_unavailable` (default: 1)

### 2.3 CNI and Networking

1. Cilium as the cross-cloud CNI with BYOCNI on EKS and AKS (ADR-008)
2. Cilium kube-proxy replacement in strict mode on EKS — no kube-proxy DaemonSet
   deployed (ADR-008)
3. AWS ENI IPAM mode with native routing (direct VPC routing, no VXLAN overlay),
   egress masquerade on `ens+` interfaces (ADR-008)

### 2.4 Gateway API

1. Gateway API for ingress — Cilium Gateway with HTTPRoute, replacing
   traditional Ingress controllers (ADR-017)
2. Gateway API CRDs v1.3.0 (experimental channel) installed via local-exec
   provisioner
3. Internal NLB scheme for platform Gateway (VPN-only access); public NLB for
   preprod Gateway (internet-facing) (ADR-017, ADR-029)
4. HTTP-to-HTTPS redirect via HTTPRoute filter with 301 permanent redirect on
   every hostname (ADR-017)
5. Cilium Gateway Envoy proxy uses reserved `ingress` identity (identity 8) for
   upstream connections — environment CiliumNetworkPolicies must allow
   `fromEntities: ["ingress"]` (ADR-008)
6. TLS secrets must be copied to `cilium-secrets` namespace as
   `<namespace>-<secret-name>` for Gateway TLS termination

### 2.5 GitOps

1. ArgoCD for GitOps delivery with Dex SAML SSO via AWS IAM Identity Center,
   multi-cluster management, and team-scoped AppProjects (ADR-021)
2. ArgoCD HA mode: controller, server, repoServer, and applicationSet each scale
   to 2 replicas when `high_availability = true` (ADR-021)
3. ArgoCD SAML app in Identity Center created manually (Terraform AWS provider
   doesn't support custom SAML apps) — documented in ADR-012
4. ArgoCD server runs with `server.insecure = true` (TLS terminated by Gateway
   NLB), default RBAC policy `role:readonly`, reconciliation timeout 180s
5. Remote cluster registration via labeled Kubernetes Secrets with optional AWS
   IAM auth (`awsAuthConfig`) for cross-account EKS access (ADR-021)
6. Bootstrap app-of-apps pattern with sync-wave annotations for ordered
   deployment of foundational services (cert-manager at wave 0,
   external-dns/external-secrets at wave 1) (ADR-021)

### 2.6 Observability

1. Hubble for Cilium network observability — relay and UI enabled by default
   (ADR-008)
2. Hubble metrics: DNS, drop, TCP, flow, port-distribution, ICMP, HTTPv2 — with
   source/destination namespace labels for DNS and drop metrics
3. Hubble TLS uses `helm` auto-generation method on AWS to avoid post-install
   hook chicken-and-egg issues with BYOCNI (ADR-008)

### 2.7 Environment Isolation

1. Namespace-based environment isolation with default-deny NetworkPolicies, resource
   quotas, and limit ranges (ADR-027)
2. Multi-app environment model — teams declare apps in `teams.hcl`, each gets an
   ArgoCD Application and optional PR preview ApplicationSet (ADR-031, ADR-032)
3. Private EKS API endpoints with Tailscale VPN for developer access (ADR-010,
   ADR-011)
4. Kyverno as the policy engine for admission control and compliance
   enforcement — supports Audit (log violations) and Enforce (block violations)
   modes per policy, with `compliance_tier` variable for tier-specific policy
   sets (ADR-014)

## 3. Networking

1. Transit Gateway hub/spoke for cross-account VPC connectivity — platform
   account as hub, shared to spokes via RAM with auto-accept enabled (ADR-034)
2. Dedicated /28 transit subnets per AZ for Transit Gateway ENI attachment,
   isolated from workload subnets (ADR-034)
3. TGW routing: hub VPC routes to spoke CIDRs via TGW, spoke VPC routes to hub
   CIDRs via TGW — generated by `setproduct()` over (route_table,
   destination_cidr) pairs (ADR-034)
4. RAM share principals specify spoke account IDs; spoke deployments reference
   the hub's RAM share ARN (ADR-034)
5. Cross-VPC DNS resolution for private EKS endpoints using custom Private
   Hosted Zones with dynamic ENI IP lookup via external data source (ADR-035)
6. Two DNS resolution modes via `dns_method` toggle: custom PHZ with A records
   (cheap, manual IP updates on cluster recreation) or Route53 Resolver
   endpoints (robust, automatic, ~$365/mo for 4 ENIs) (ADR-035)
7. EKS-managed Route53 PHZs are inaccessible via standard APIs — platform
   maintains its own PHZs for cross-VPC resolution (ADR-035)
8. SSM Session Manager bastion for private cluster access without SSH or VPN —
   no inbound security group rules (SSH disabled), egress limited to HTTPS (443)
   to the cluster API security group (ADR-020)
9. Tailscale Operator as subnet router advertising VPC CIDR (`10.100.0.0/16`) to
   the tailnet — userspace mode (`TS_USERSPACE=true` via ProxyClass) for Cilium
   compatibility (ADR-011)
10. Tailscale split DNS managed by the `tailscale` K8s unit (not
    `tailscale-admin`) with `depends_on` on the Connector — created only after
    the subnet router is online (ADR-011)
11. Tailscale OAuth credentials sourced from AWS Secrets Manager via generated
    data source; module is cloud-agnostic, only live unit provider config is
    AWS-specific (ADR-011)
12. Tailscale ACL `autoApprovers` automatically approve VPC subnet routes
    advertised by devices tagged `tag:k8s-operator` — avoids manual route
    approval on each recreation (ADR-011)
13. Route53 subdomain delegation for per-environment DNS zones — NS records from
    parent zone to child (ADR-030)
14. cert-manager with DNS-01 challenges via Route53 for TLS certificates on
    private endpoints — ACME production server, ClusterIssuer per cluster,
    wildcard certificates supported (ADR-030)
15. ExternalDNS with Gateway API source support (HTTPRoute, GRPCRoute, TLSRoute)
    and IRSA for Route53 record management

## 4. Security

### 4.1 IAM and Access Control

1. Least-privilege IAM via purpose-built roles: PlatformAdmin (kubectl, SSM,
   debugging), PlatformDeployer (Terragrunt apply, Helm/K8s providers),
   DeveloperAccess (namespace-scoped kubectl), TerraformStateAccess (S3 +
   DynamoDB) (ADR-007)
2. Terragrunt providers assume PlatformDeployer via `root.hcl`; Helm/K8s exec
   auth uses PlatformDeployer; kubectl uses PlatformAdmin; state backend uses
   TerraformStateAccess (ADR-007)
3. OrganizationAccountAccessRole retained as break-glass only — not used for
   day-to-day operations (ADR-007)
4. IRSA (IAM Roles for Service Accounts) for pod-level AWS identity — no static
   credentials in workloads. OIDC provider per cluster with
   `sts.amazonaws.com` client ID (ADR-018)
5. IAM Identity Center for federated access — permission sets with managed and
   inline policies, configurable session duration, group-to-account assignments
   for cross-account access without IAM users in workload accounts (ADR-007)

### 4.2 Organizational Policies

1. AWS Organizations with 8 SCPs enforcing guardrails at the API level — no
   opt-out possible (ADR-003):
   - `baseline-guardrails`: prevent org departure, root user lockdown, protect
     OrganizationAccountAccessRole, deny region/password policy changes
   - `protect-security-services`: prevent disabling CloudTrail, Config,
     GuardDuty, Security Hub, Access Analyzer, VPC Flow Logs
   - `enforce-encryption`: require EBS/RDS encryption, protect KMS keys, enforce
     IMDSv2
   - `deny-regions`: restrict to us-east-1 and us-west-2 with global service
     exemptions
   - `protect-data-and-network`: block S3 public access changes, default VPC
     creation, external RAM sharing, backup deletion
   - `require-tagging`: deny resource creation without Environment, ManagedBy,
     Owner tags
   - `restrict-iam-users`: deny IAM user/access key creation, force federation
   - `hipaa-eligible-services`: allowlist of HIPAA BAA-covered services
     (optional, off by default)
2. SCP attachment strategy: root gets 4 policies, Platform OU gets +1 (5 total),
   Workloads OU gets +3 (7 total) (ADR-003)

### 4.3 Authentication and Secrets

1. GitHub Actions OIDC federation for keyless CI/CD — branch and event scoped
   trust policies with subject claim format
   `repo:<org>/<repo>:ref:refs/heads/<branch>` and
   `repo:<org>/<repo>:<event>` (ADR-036)
2. External Secrets Operator with AWS Secrets Manager and SSM Parameter Store
   backends via IRSA — actions scoped to `GetSecretValue`, `GetParameter`, and
   `Decrypt` with configurable path prefixes (ADR-019, ADR-024)
3. ClusterSecretStore per cluster connecting External Secrets Operator to AWS
   backends (ADR-024)

### 4.4 Encryption and Audit

1. KMS customer-managed key per EKS cluster for Kubernetes secrets envelope
   encryption, with automatic rotation and alias `{cluster_name}-eks`
2. CloudTrail per-account audit logging with S3 storage (versioning enabled,
   public access blocked), KMS encryption, and log file validation (SHA-256
   digest) (ADR-037)
3. CloudTrail CloudWatch integration: log group
   `/aws/cloudtrail/{trail-name}` with configurable retention (default 30
   days) (ADR-037)
4. Secrets Manager alarm: metric filter detects GetSecretValue, PutSecretValue,
   CreateSecret, DeleteSecret — alarm fires on any write activity with 5-minute
   evaluation period (ADR-037)
5. S3 log lifecycle: expires after `log_retention_days` (default 90 days)
   (ADR-037)
6. ECR tag immutability and scan-on-push enabled; cross-account pull via
   repository resource policies granting BatchGetImage and
   GetDownloadUrlForLayer (ADR-028)
7. ECR lifecycle policies: expire untagged images after 7 days, keep last 50
   tagged images per repository (ADR-028)
8. VPC flow logs for network traffic auditing

### 4.5 Network Security

1. Default-deny ingress NetworkPolicies on all environment namespaces with Cilium
   enforcement at the eBPF level (ADR-027)
2. CiliumNetworkPolicy per namespace allowing traffic from Gateway Envoy
   (`ingress` entity), remote nodes, and host network namespace (ADR-027)
3. Standard Kubernetes NetworkPolicy stack per environment: default-deny-ingress,
   allow-gateway-ingress (from gateway and kube-system namespaces),
   allow-dns-egress (UDP/TCP port 53), implicit allow all egress (ADR-027)

## 5. Compliance

1. Compliance tier model: Standard (SOC 2), HIPAA, PCI — declared per workload
   via `compliance_tier` in `workload.hcl` (ADR-013)
2. Per-tier controls (ADR-013):
   - **Standard**: shared cluster, shared VNet, platform-managed keys,
     allow-default network policy, 30-day log retention
   - **HIPAA**: dedicated cluster, isolated VNet (no hub peering),
     customer-managed keys (CMK), host encryption required, 365-day log
     retention, HIPAA BAA service allowlist SCP
   - **PCI**: dedicated cluster, CDE-segmented VNet, CMK with rotation policy,
     deny-all network policy, WAF required on all ingress, IDS/IPS required,
     365-day log retention
3. Tag propagation: `ComplianceTier` tag on all resources for audit queries,
   plus required tags Environment, ManagedBy, Owner enforced by SCP
4. SCP enforcement at the AWS API level — no opt-out possible (ADR-003)
5. ResourceQuotas enforce resource limits at the scheduler level — default 4 CPU,
   8Gi memory, 20 pods per environment namespace (ADR-027)
6. LimitRange defaults per container: 500m/512Mi limits, 100m/128Mi requests
   (ADR-027)
7. NetworkPolicies enforce isolation at the kernel level (Cilium eBPF) (ADR-008)
8. Architecture Decision Records (ADRs) documenting every significant design
   choice — 38 ADRs and growing

## 6. CI/CD and Automation

### 6.1 platctl CLI

1. `platctl` Go CLI for DAG-aware platform operations (ADR-038):
   - `bootstrap`: deploy full platform stack resolving dependency graph
   - `teardown`: destroy in reverse dependency order
   - `validate`: verify deployed infrastructure with targeted checks
   - `kubeconfig`: configure kubectl contexts for all clusters
   - `status`: display last operation state from `.platctl-state.json` with
     per-unit status (completed, failed, skipped, pending) and durations
   - `--dry-run`, `--env`, `--check` flags for scoped operations
   - `--resume` to continue from incomplete runs (skipping completed units)
   - `--concurrency` for parallel execution with wave decomposition
2. `.platctl.yaml` configuration file for environment definitions, dependency
   graph, and hook system (ADR-038)
3. platctl hook types for complex deployment sequences (ADR-038):
   - `crd_two_stage`: applies operator first (creates CRDs), then full apply
   - `secret_cleanup`: force-deletes orphaned Secrets Manager secrets before
     apply
   - `eni_ip_validation`: validates EKS ENI IPs before cross-VPC DNS apply

### 6.2 GitHub Actions

1. GitHub Actions with OIDC federation for CI/CD — two deployments: platform
   account ECR push role and test account Terratest role (ADR-036)
2. OIDC trust policies scoped by branch (`refs/heads/main`) and event type
   (`pull_request`) — fork PRs blocked from OIDC by GitHub default (ADR-036)
3. PR preview environments via ArgoCD ApplicationSet PR generator — apps with
   `preview = true` get ephemeral deployments per open PR (ADR-032)
4. Kustomize `commonLabels` on both stable (`app.kubernetes.io/instance: stable`)
   and preview (`app.kubernetes.io/instance: pr-{{.number}}`) Applications to
   prevent label selector collision between production and preview pods
   (ADR-032)
5. Kustomize patches rewrite HTTPRoute hostnames and backendRefs for preview
   deployments (ADR-032)

### 6.3 Code Quality

1. Pre-commit hooks (`.githooks/pre-commit`) for `tofu fmt`, `terragrunt hclfmt`,
   and `tofu validate` on staged files
2. Markdown linting in CI for documentation quality
3. terraform-docs auto-generation for module READMEs with `.terraform-docs.yml`
   config

## 7. Testing

1. Terratest (Go) for module integration tests — tests live in
   `infra/tests/aws/<module>/` (ADR-036)
2. Plan-only tests for modules that cannot be safely apply/destroyed in CI
3. Test fixtures in `infra/tests/aws/<module>/fixtures/` for reusable test
   configurations
4. Must use OpenTofu binary: set `TerraformBinary: "tofu"` in test options
5. GitHub OIDC provides test accounts with scoped IAM roles for CI runs —
   branch-scoped trust policies prevent unauthorized access (ADR-036)

## 8. Multitenancy

1. Namespace isolation as the default environment boundary — each team gets a
   `team-<name>` namespace (ADR-027)
2. Self-service via `teams.hcl` with nested `apps` map: each team declares
   multiple apps with `repo_url`, `repo_path`, `repo_branch`, and `preview`
   flag (ADR-031)
3. ECR naming convention: `team-<team>/<app>` (e.g., `team-alpha/demo`) —
   supports monorepo and multi-repo teams (ADR-031)
4. ArgoCD creates one Application per app entry and one ApplicationSet per
   preview-enabled app (ADR-031, ADR-032)
5. ResourceQuotas cap CPU (4), memory (8Gi), and pod count (20) per team
   namespace — overridable via `resource_quota` in teams.hcl (ADR-027)
6. LimitRange per namespace sets default container resource requests (100m CPU,
   128Mi memory) and limits (500m CPU, 512Mi memory) (ADR-027)
7. AppProject sourceRepos whitelist restricts which Git repos each team can
   deploy from; deployable resource kinds are restricted (ADR-021)
8. Teams own their app manifests in their own repos — the platform provides the
   deployment pipeline via ArgoCD Applications pointing at team repos
9. vCluster support deferred — OSS cannot sync HTTPRoute CRDs to the host
   cluster's Gateway (ADR-033)

## 9. Module Design

1. Universal `create` toggle on every resource-creating module for selective
   deployment without config removal
2. Cloud-agnostic shared modules use `cloud_provider` variable for cloud-specific
   logic
3. Cross-cloud interface contract: `network_id`, `subnet_ids`,
   `kubernetes_subnet_id` outputs for downstream modules
4. All Terragrunt dependency blocks include `mock_outputs` for plan/destroy
   resilience — destroy works even when upstream dependencies are already gone
5. `versions.tf` in every module specifying required provider versions
6. All modules documented with README using terraform-docs for auto-generated
   inputs/outputs
7. Related ADRs referenced in each module's README

## 10. Secrets Management

1. External Secrets Operator deployed per cluster with IRSA for AWS API access
   (ADR-019)
2. ClusterSecretStore per cluster connecting to AWS Secrets Manager
   (`GetSecretValue`, `DescribeSecret`) and SSM Parameter Store
   (`GetParameter`, `GetParametersByPath`) (ADR-024)
3. KMS decrypt permissions for encrypted secrets with configurable key ARN list
   (ADR-024)
4. Path-based scoping via `secret_path_prefix` and `ssm_path_prefix` to restrict
   which secrets each cluster can access (ADR-024)
5. Tailscale OAuth credentials stored in AWS Secrets Manager, sourced via
   generated data source in the tailscale module (ADR-011)
6. No static credentials in workloads — all AWS access via IRSA, all Kubernetes
   secrets via External Secrets Operator (ADR-018, ADR-019)

## 11. Documentation

1. Module READMEs with terraform-docs auto-generated inputs/outputs and
   hand-written usage examples, notes, and related ADRs
2. `.terraform-docs.yml` config at repo root with `sections.hide: [header]` to
   prevent duplicate H1 headings
3. Terragrunt unit READMEs documenting module source, dependencies, key inputs,
   and apply commands with correct AWS_PROFILE
4. Architecture Decision Records for every significant design choice (38 ADRs)
5. Operational runbooks for common tasks (environment onboarding, app deployment,
   cluster access, ArgoCD SSO)
6. Onboarding guide for new team members
7. Compliance control mappings (SOC2, HIPAA, PCI-DSS)
8. Interview prep document mapping platform architecture to discussion topics
