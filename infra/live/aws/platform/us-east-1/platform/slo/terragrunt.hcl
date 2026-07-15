include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.observability_slo
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

# SLOs evaluate against metrics in the hub Prometheus + render dashboards via the observability Grafana
# sidecar. Depend on observability so the namespace exists and the rule/dashboard discovery is in place.
dependency "observability" {
  config_path = "../observability"

  mock_outputs = {
    namespace = "observability"
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
  create    = true
  namespace = dependency.observability.outputs.namespace

  helm_chart_version = include.base.locals.helm_versions.sloth

  # SLO dashboard (14643) queries the FEDERATED Mimir datasource (`mimir-all` = platform|preprod) so it shows
  # BOTH the platform-tenant apiserver SLO (Sloth controller) AND the preprod-tenant per-app SLOs (the Mimir-ruler
  # burn-rate rules from observability-mimir app_slos). Needs enable_federated_datasource on the mimir unit.
  slo_dashboard_datasource_uid = "mimir-all"

  # First SLO: API server request availability — the one control-plane signal EKS exposes, always has
  # traffic. Sloth fills {{.window}} per burn-rate window. Burn-rate alerts route via the P4 Alertmanager.
  #
  # Stack self-SLOs (meta-monitoring): error-budget the observability stack's own request success rate —
  # today MimirComponentDown/LokiDown/TempoComponentDown etc. are plain up/down + error-rate alerts with no
  # budget. One combined ingest+query success-rate SLO per store (not split by route — a meta-monitoring
  # signal doesn't need 6 SLOs; split later only if ingest vs. query failures need distinguishing budgets).
  # All three metrics are scraped LOCALLY by the hub's kube-prometheus-stack Prometheus (Mimir/Loki/Tempo all
  # run on the hub), so Sloth (not the Mimir-ruler app_slos path) is the right mechanism — verified live.
  slos = [
    {
      name        = "kubernetes-apiserver"
      service     = "kubernetes-apiserver"
      slo_name    = "requests-availability"
      description = "API server request availability (non-5xx responses)."
      objective   = 99.9
      error_query = "sum(rate(apiserver_request_total{code=~\"5..\"}[{{.window}}]))"
      total_query = "sum(rate(apiserver_request_total[{{.window}}]))"
      alert_name  = "K8sApiserverAvailability"
      runbook_url = "https://github.com/asanexample/platform/blob/main/docs/runbooks/observability-alerts.md#platform-slos"
    },
    {
      name        = "mimir"
      service     = "mimir"
      slo_name    = "requests-availability"
      description = "Mimir (metrics store) request success rate — ingest + query, all routes."
      objective   = 99.9
      error_query = "sum(rate(cortex_request_duration_seconds_count{status_code=~\"5..\"}[{{.window}}]))"
      total_query = "sum(rate(cortex_request_duration_seconds_count[{{.window}}]))"
      alert_name  = "MimirRequestsAvailability"
      runbook_url = "https://github.com/asanexample/platform/blob/main/docs/runbooks/observability-alerts.md#platform-slos"
    },
    {
      name        = "loki"
      service     = "loki"
      slo_name    = "requests-availability"
      description = "Loki (log store) request success rate — ingest + query, all routes/tenants."
      objective   = 99.9
      error_query = "sum(rate(loki_request_duration_seconds_count{status_code=~\"5..\"}[{{.window}}]))"
      total_query = "sum(rate(loki_request_duration_seconds_count[{{.window}}]))"
      alert_name  = "LokiRequestsAvailability"
      runbook_url = "https://github.com/asanexample/platform/blob/main/docs/runbooks/observability-alerts.md#platform-slos"
    },
    {
      name        = "tempo"
      service     = "tempo"
      slo_name    = "requests-availability"
      description = "Tempo (trace store) request success rate — ingest + query, all routes."
      objective   = 99.9
      error_query = "sum(rate(tempo_request_duration_seconds_count{status_code=~\"5..\"}[{{.window}}]))"
      total_query = "sum(rate(tempo_request_duration_seconds_count[{{.window}}]))"
      runbook_url = "https://github.com/asanexample/platform/blob/main/docs/runbooks/observability-alerts.md#platform-slos"
      alert_name  = "TempoRequestsAvailability"
    },
    # Control-plane / provisioning SLIs (#102 phase). Crossplane core reconcile is DELIBERATELY NOT here —
    # verified live that the platform hub's `crossplane` PodMonitor (namespace observability) selects
    # `port: metrics`, but the deployed crossplane pod declares no port named "metrics" (only readyz/webhooks)
    # — zero scrape targets despite enable_crossplane_pod_monitor=true. Requires instrumentation; tracked as
    # a follow-up issue rather than shipping a broken/always-absent SLO.
    {
      name        = "argo-rollouts"
      service     = "argo-rollouts"
      slo_name    = "reconcile-success"
      description = "Argo Rollouts controller reconcile success rate (all Rollouts, both clusters)."
      objective   = 99
      # rollout_reconcile_error is sparse (errors are rare) — `or vector(0)` avoids an absent numerator
      # reading as "no data" instead of "zero errors" (same pattern app_slos already uses).
      error_query = "(sum(rate(rollout_reconcile_error[{{.window}}])) or vector(0))"
      total_query = "sum(rate(rollout_reconcile_count[{{.window}}]))"
      alert_name  = "ArgoRolloutsReconcile"
      runbook_url = "https://github.com/asanexample/platform/blob/main/docs/runbooks/observability-alerts.md#platform-slos"
    },
    {
      name        = "kyverno-admission"
      service     = "kyverno"
      slo_name    = "admission-latency"
      description = "Kyverno admission review latency — 99% complete within 1s (le=\"1.0\", an actual histogram bucket boundary)."
      objective   = 99
      error_query = "(sum(rate(kyverno_admission_review_duration_seconds_count[{{.window}}])) - sum(rate(kyverno_admission_review_duration_seconds_bucket{le=\"1.0\"}[{{.window}}])))"
      total_query = "sum(rate(kyverno_admission_review_duration_seconds_count[{{.window}}]))"
      alert_name  = "KyvernoAdmissionLatency"
      runbook_url = "https://github.com/asanexample/platform/blob/main/docs/runbooks/observability-alerts.md#platform-slos"
    },
    {
      name        = "jit-activation"
      service     = "activation-operator"
      slo_name    = "activation-outcome"
      description = "JIT privilege activation (mint + revoke) success rate. Low-volume, break-glass-shaped traffic — expect long data gaps between operations; that's normal, not a monitoring failure."
      objective   = 99
      # Combined mint+revoke: each signal individually is too sparse (mint hasn't fired in 13d as of this
      # writing) for a meaningful standalone SLO. `activation_mint_failures` currently has NO series at all
      # (zero mint failures ever recorded, and this OTel counter apparently isn't exported until its first
      # increment) — `or vector(0)` treats "no failures recorded" as 0, not "no data".
      error_query = "((sum(rate(activation_mint_failures[{{.window}}])) or vector(0)) + (sum(rate(activation_revoke_failures[{{.window}}])) or vector(0)))"
      total_query = "(sum(rate(activation_mint_duration_count[{{.window}}])) or vector(0)) + (sum(rate(activation_revoke_duration_count[{{.window}}])) or vector(0))"
      alert_name  = "JitActivationOutcome"
      runbook_url = "https://github.com/asanexample/platform/blob/main/docs/runbooks/observability-alerts.md#platform-slos"
    },
  ]

  tags = include.base.locals.tags
}
