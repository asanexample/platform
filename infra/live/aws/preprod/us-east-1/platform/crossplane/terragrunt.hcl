include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.crossplane
}

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_id                    = "mock-cluster"
    cluster_endpoint              = "https://mock-endpoint"
    cluster_certificate_authority = "bW9jaw=="
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

dependency "node_groups" {
  config_path = "../node-groups"

  mock_outputs                            = {}
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# Ordering only: Crossplane's rbac-manager authors wildcard provider ClusterRoles at runtime that the
# preprod Kyverno (Enforce) restrict-wildcard-rbac policy would deny unless crossplane-system is excluded.
# The policy unit carries that exclusion (extra_exclude_principals/namespaces), so it must apply first.
dependency "policy" {
  config_path = "../policy"

  mock_outputs                            = {}
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

generate "helm_provider" {
  path      = "helm-provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "helm" {
      kubernetes = {
        host                   = "${dependency.eks.outputs.cluster_endpoint}"
        cluster_ca_certificate = base64decode("${dependency.eks.outputs.cluster_certificate_authority}")

        exec = {
          api_version = "client.authentication.k8s.io/v1beta1"
          command     = "aws"
          args        = ["eks", "get-token", "--cluster-name", "${dependency.eks.outputs.cluster_id}", "--region", "${include.base.locals.region}", "--role-arn", "${include.base.locals.deployer_role_arn}"]
        }
      }
    }
  EOF
}

inputs = {
  create = true

  cluster_name = dependency.eks.outputs.cluster_id
  region       = include.base.locals.region
  account_id   = include.base.locals.account_id # preprod — unused until AWS providers land (P2b)

  helm_chart_version = include.base.locals.helm_versions.crossplane
  helm_wait          = true

  # Federated environment control plane (ADR-048). P2b: the full environment footprint — K8s (provider-kubernetes) +
  # AWS (provider-aws iam/eks locally; ecr cross-account into the platform account via assumeRoleChain).
  # ADR-073 Phase A: provider-aws-s3 added for the self-service resource paved road (S3 first). The module loop
  # spins up provider-aws-s3 from the registry; SQS/SNS/DynamoDB follow in Phase A.1.
  provider_services = ["ecr", "iam", "eks", "s3"]

  enable_kubernetes_provider = true
  # provider-kubernetes stays hostNetwork + list index 0 (its P2a config) so it does NOT churn when the aws
  # providers are added — keeping it on its current node where its (hardcoded :8080/:8081/9443) ports are
  # free. Its Object conversion webhook needs hostNetwork to be apiserver-reachable under the overlay.
  kubernetes_provider_hostnetwork = true

  functions = [
    { name = "function-go-templating", package = "xpkg.upbound.io/crossplane-contrib/function-go-templating:v0.12.1" },
    { name = "function-auto-ready", package = "xpkg.upbound.io/crossplane-contrib/function-auto-ready:v0.6.5" },
    { name = "function-environment-configs", package = "xpkg.upbound.io/crossplane-contrib/function-environment-configs:v0.7.1" },
  ]

  enable_environment_api = true

  # A7 cutover: the retired v1 `environment` module no longer owns the shared `environment-developer` ClusterRole, so the
  # environment chart creates it (the Composition's per-environment RoleBindings bind to it).
  create_developer_cluster_role = true

  # ArgoCD delivers the XEnvironment claims (the `environments` registry-sync app, gitops/environments) from
  # the platform cluster, authenticating to this remote cluster via the cross-account `ArgoCD` IAM role — so its
  # admission username is that role's
  # assumed-role ARN, not the in-cluster argocd SA. Allow it past restrict-environment-control-plane (ADR-046/048).
  # Scoped to THIS (preprod) account; the `ArgoCD` role + EKS access entry are platform-owned.
  # PlatformDeployer is the IaC principal that OWNS the control-plane resources (it creates the ProviderConfigs
  # via this very unit) — exclude it too, or any re-apply that re-patches a ProviderConfig is denied at admission
  # (the initial create slipped in before this policy existed). Same convention as the policy module's deny-set.
  environment_policy_values = {
    extraExcludePrincipals = [
      "arn:aws:sts::${include.base.locals.account_ids["preprod"]}:assumed-role/ArgoCD/*",
      "arn:aws:sts::${include.base.locals.account_ids["preprod"]}:assumed-role/PlatformDeployer/*",
    ]
    # v3 cutover (ADR-067): activate restrict-environment-envelope (#387) — the XEnvironment envelope check
    # (team-matches-product, stage/tier/residency/quota within the Team envelope, policyStatements deny-set).
    enableEnvironmentEnvelope = true
    # The envelope soaked in Audit through the rebuild (one clean reconcile, the v2 A6 precedent) with ZERO
    # violations across both environments + their workloads, so it is now ENFORCE — out-of-envelope XEnvironment
    # claims (wrong team-for-product, out-of-ladder stage/tier, over-quota, escalating policyStatements) are
    # rejected at admission, not just audited. envelopeFailureAction governs only the envelope (the v2
    # restrict-environment-envelope was removed at the cutover).
    envelopeFailureAction = "Enforce"
  }

  # Environment provisioning identity (P2b): scoped IAM + EKS Pod Identity locally, plus assume the platform ECR
  # role for cross-account repos. The deny-escalation permissions boundary is created in the module.
  enable_environment_provisioning = true
  ecr_provisioner_role_arn        = "arn:aws:iam::${include.base.locals.account_ids["platform"]}:role/crossplane-ecr-provisioner"

  # Teardown: force-delete orphaned environment ECR repos (team-*) the Composition created cross-account. Uses the
  # platform PlatformDeployer (assumable by the teardown profile); the in-account ecr-provisioner role is only
  # reachable via the provider's assumeRoleChain, not a local-exec. Sibling of the IAM orphan sweep (ADR-046/048).
  ecr_orphan_sweep_role_arn = "arn:aws:iam::${include.base.locals.account_ids["platform"]}:role/PlatformDeployer"

  # Cluster constants for the Composition's EnvironmentConfig: platform ECR registry + cross-account pull.
  ecr_registry                 = "${include.base.locals.account_ids["platform"]}.dkr.ecr.${include.base.locals.region}.amazonaws.com"
  environment_pull_account_ids = [include.base.locals.account_ids["preprod"], include.base.locals.account_ids["prod"]]

  # Environment app ingress domain — the Composition derives each app's allowed route hostnames as
  # <app>-<team>.<base_domain> + the <app>-<team>-pr-* preview wildcard (ADR-060). Matches the argocd-apps
  # preview_domain (which injects the actual route hostnames from the same convention).
  base_domain = "preprod.aws.refplat.org"

  # Management account ID — the Composition's DeveloperAccess-<team> trust allows the per-team SSO permission
  # set (Dev-<team>) in both the management and preprod accounts to assume the role (P2c, ADR-039).
  management_account_id = include.base.locals.account_ids["mgmt"]

  # Team CRs are git-native (ADR-063): authored as YAML in gitops/teams/ and ArgoCD-synced (the `teams` app in
  # the argocd-apps unit). The v2 crossplane-teams Helm projection was removed at the v3 cutover; the Team CRD
  # itself still ships with the environment chart (enable_environment_api). Source of truth for the envelope Kyverno reads
  # is the git-synced Team CR.

  # Destroy-time CR finalizer cleanup auth (scripts/k8s-finalizer-clear.sh) — see crd_finalizer_cleanup.
  deployer_role_arn      = include.base.locals.deployer_role_arn
  finalizer_clear_script = "${get_repo_root()}/scripts/k8s-finalizer-clear.sh"

  tags = include.base.locals.tags
}
