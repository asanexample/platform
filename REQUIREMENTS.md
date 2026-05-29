# Platform Requirements

## 1. Architecture

1. Use OpenTofu with Terragrunt for infrastructure management across AWS, Azure,
   and GCP (ADR-016)
2. Cloud-aware state management: S3 with DynamoDB locking for AWS, Azure Blob
   Storage for Azure — root `root.hcl` routes automatically based on directory
   path (ADR-002)
3. Monorepo structure with three layers: reusable modules (`infra/modules/`),
   cloud-specific modules (`infra/modules/aws/`, `azure/`, etc.), and live
   environment configs (`infra/live/{cloud}/{env}/{region}/{workload}/`)
4. Support multiple environments per cloud: management, platform, preprod, prod
   (AWS); dev, ops (Azure); ops (GCP)
5. Multi-account AWS organization with purpose-built IAM roles for cross-account
   access (ADR-004, ADR-007)
6. Hierarchical CIDR allocation with /16 per environment, cross-cloud /14
   summaries (ADR-015)
7. Network architecture optimized for Kubernetes with 3-AZ support, private/public/
   airgapped topology modes

## 2. Kubernetes Platform

1. Cilium as the cross-cloud CNI with BYOCNI on EKS and AKS (ADR-008)
2. Gateway API for ingress — Cilium Gateway with HTTPRoute, replacing traditional
   Ingress controllers (ADR-017)
3. ArgoCD for GitOps delivery with Dex SAML SSO, multi-cluster management, and
   team-scoped AppProjects (ADR-021)
4. Namespace-based tenant isolation with default-deny NetworkPolicies, resource
   quotas, and limit ranges (ADR-027)
5. Multi-app tenant model — teams declare apps in `teams.hcl`, each gets an
   ArgoCD Application and optional PR preview ApplicationSet (ADR-031, ADR-032)
6. EKS component separation into ordered units: eks → cilium → node-groups →
   eks-addons (ADR-009)
7. Private EKS API endpoints with Tailscale VPN for developer access (ADR-010,
   ADR-011)
8. Kyverno as the policy engine for admission control and compliance enforcement
   (ADR-014)

## 3. Networking

1. Transit Gateway hub/spoke for cross-account VPC connectivity — platform account
   as hub, shared to spokes via RAM (ADR-034)
2. Cross-VPC DNS resolution for private EKS endpoints using custom Private Hosted
   Zones with dynamic ENI IP lookup (ADR-035)
3. SSM Session Manager bastion for private cluster access without SSH or VPN
   (ADR-020)
4. Tailscale Operator as subnet router for developer VPN access — userspace mode
   for Cilium compatibility (ADR-011)
5. Route53 subdomain delegation for per-environment DNS zones (ADR-030)
6. cert-manager with DNS-01 challenges for TLS certificates on private endpoints

## 4. Security

1. Least-privilege IAM via purpose-built roles: PlatformAdmin, PlatformDeployer,
   DeveloperAccess, TerraformStateAccess (ADR-007)
2. AWS Organizations with SCPs enforcing encryption, region restrictions, IMDSv2,
   root user protection, security service protection, and tagging (ADR-003)
3. IRSA (IAM Roles for Service Accounts) for pod-level AWS identity — no static
   credentials in workloads (ADR-018)
4. GitHub Actions OIDC federation for keyless CI/CD — branch and event scoped
   trust policies (ADR-036)
5. External Secrets Operator with AWS Secrets Manager and SSM Parameter Store
   backends (ADR-019, ADR-024)
6. CloudTrail per-account audit logging with KMS encryption and secrets access
   alarms (ADR-037)
7. ECR tag immutability and cross-account pull via resource policies (ADR-028)
8. Default-deny ingress NetworkPolicies on all tenant namespaces with Cilium
   enforcement at the eBPF level

## 5. Compliance

1. Compliance tier model: Standard (SOC 2), HIPAA, PCI — declared per workload
   via `compliance_tier` in `workload.hcl` (ADR-013)
2. Tag propagation: `ComplianceTier` tag on all resources for audit queries
3. SCP enforcement at the AWS API level — no opt-out possible (ADR-003)
4. ResourceQuotas enforce resource limits at the scheduler level
5. NetworkPolicies enforce isolation at the kernel level (Cilium eBPF)
6. Architecture Decision Records (ADRs) documenting every significant design
   choice — 38 ADRs and growing

## 6. CI/CD and Automation

1. `platctl` Go CLI for DAG-aware platform operations: bootstrap, teardown,
   validate, kubeconfig (ADR-038)
2. GitHub Actions with OIDC federation for CI/CD (ADR-036)
3. PR preview environments via ArgoCD ApplicationSet PR generator (ADR-032)
4. Pre-commit hooks for `tofu fmt`, `terragrunt hclfmt`, and `tofu validate`
5. Markdown linting in CI for documentation quality

## 7. Testing

1. Terratest (Go) for module integration tests — tests live in
   `infra/tests/aws/<module>/`
2. Plan-only tests for modules that cannot be safely apply/destroyed in CI
3. Must use OpenTofu binary: set `TerraformBinary: "tofu"` in test options
4. GitHub OIDC provides test accounts with scoped IAM roles for CI runs

## 8. Multitenancy

1. Namespace isolation as the default tenant boundary — each team gets a
   `team-<name>` namespace (ADR-027)
2. Self-service via `teams.hcl`: 5 lines adds a team with namespace, quotas,
   network policies, ECR repo, OIDC trust, and ArgoCD Application (ADR-031)
3. ResourceQuotas cap CPU, memory, and pod count per team
4. AppProject whitelists restrict deployable resource kinds
5. Teams own their app manifests in their own repos — the platform provides the
   deployment pipeline
6. vCluster support deferred — OSS cannot sync HTTPRoute CRDs to the host
   cluster's Gateway (ADR-033)

## 9. Module Design

1. Universal `create` toggle on every resource-creating module for selective
   deployment without config removal
2. Cloud-agnostic shared modules use `cloud_provider` variable for cloud-specific
   logic
3. Cross-cloud interface contract: `network_id`, `subnet_ids`,
   `kubernetes_subnet_id` outputs for downstream modules
4. All modules documented with README using terraform-docs for auto-generated
   inputs/outputs
5. Related ADRs referenced in each module's README

## 10. Documentation

1. Module READMEs with terraform-docs auto-generated inputs/outputs and
   hand-written usage examples
2. Terragrunt unit READMEs documenting module source, dependencies, key inputs,
   and apply commands
3. Architecture Decision Records for every significant design choice
4. Operational runbooks for common tasks (tenant onboarding, app deployment,
   cluster access, ArgoCD SSO)
5. Onboarding guide for new team members
6. Compliance control mappings (SOC2, HIPAA, PCI-DSS)
7. Interview prep document mapping platform architecture to discussion topics
