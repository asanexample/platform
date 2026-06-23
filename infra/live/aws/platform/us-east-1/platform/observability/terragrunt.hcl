include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.observability
}

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_id                    = "mock-cluster"
    cluster_endpoint              = "https://mock-endpoint"
    cluster_certificate_authority = "bW9jaw=="
    oidc_provider_arn             = "arn:aws:iam::000000000000:oidc-provider/mock"
    oidc_provider_url             = "oidc.eks.mock.amazonaws.com/id/mock"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

dependency "node_groups" {
  config_path = "../node-groups"

  mock_outputs                            = {}
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

dependency "sns_notifications" {
  config_path = "../sns-notifications"

  mock_outputs = {
    topic_arn = "arn:aws:sns:us-east-1:000000000000:platform-alerts"
  }
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

generate "kubernetes_provider" {
  path      = "kubernetes-provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "kubernetes" {
      host                   = "${dependency.eks.outputs.cluster_endpoint}"
      cluster_ca_certificate = base64decode("${dependency.eks.outputs.cluster_certificate_authority}")

      exec {
        api_version = "client.authentication.k8s.io/v1beta1"
        command     = "aws"
        args        = ["eks", "get-token", "--cluster-name", "${dependency.eks.outputs.cluster_id}", "--region", "${include.base.locals.region}", "--role-arn", "${include.base.locals.deployer_role_arn}"]
      }
    }
  EOF
}

inputs = {
  create       = true
  cluster_name = dependency.eks.outputs.cluster_id
  aws_region   = include.base.locals.region

  # Multi-cluster dimension: stamp the clean env name (`platform`) as the `cluster` label, not the raw EKS
  # cluster ID — so the single pane reads `platform`/`preprod` (== tenant == env), consistently (#630).
  cluster_label = include.base.locals.env

  helm_chart_version = include.base.locals.helm_versions.kube_prometheus_stack
  helm_wait          = true

  # Sizing follows cost_profile (dev = single-replica; prod = HA, needs >=3 nodes / 2-3 AZs).
  high_availability = include.base.locals.high_availability
  # Prometheus + Alertmanager on durable gp3 PVCs (the eks-addons gp3 default StorageClass, #102 P2).
  use_persistent_storage = true
  storage_class          = "gp3"

  # Ship metrics to Mimir for durable, long-range storage (#102 P2). Tenant = platform (the hub's own
  # metrics). Setting this also makes the Mimir datasource Grafana's default (Prometheus stays selectable).
  # Empty when Mimir is disabled (cost-profile toggle) — Prometheus keeps local retention only.
  mimir_remote_write_url = include.base.locals.enable_mimir ? "http://mimir-gateway.observability.svc/api/v1/push" : ""

  # Alertmanager → SNS (critical alerts → email)
  oidc_provider_arn = dependency.eks.outputs.oidc_provider_arn
  oidc_provider_url = dependency.eks.outputs.oidc_provider_url
  alerts_topic_arn  = dependency.sns_notifications.outputs.topic_arn

  # Slack alerting: Alertmanager Slack receiver, webhook synced from Secrets Manager via External Secrets
  # (manually created — see docs/runbooks/observability-alerts.md). warning → Slack, critical → Slack + SNS.
  slack_webhook_secret_name = "platform/observability/slack-webhook"
  # PagerDuty: critical alerts page via Events API v2; routing key synced from SM via External Secrets.
  pagerduty_routing_key_secret_name = "platform/observability/pagerduty-routing-key"

  # P5a — cloud-resource metrics: Grafana CloudWatch datasource (query-time, zero storage). Grafana's SA
  # gets CloudWatch read via Pod Identity. Broad AWS-resource coverage (NLB/S3/TGW/NAT/Route53/EKS).
  cloudwatch_enabled = true

  # Grafana served Tailscale-only via the platform internal Gateway (gateway-config adds the HTTPRoute).
  grafana_hostname = "grafana.aws.refplat.org"

  # Destroy-time namespace drain auth (scripts/k8s-finalizer-clear.sh) — see the module's namespace_drain.
  deployer_role_arn      = include.base.locals.deployer_role_arn
  finalizer_clear_script = "${get_repo_root()}/scripts/k8s-finalizer-clear.sh"

  tags = include.base.locals.tags
}
