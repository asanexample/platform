variable "create" {
  description = "Controls whether resources are created (cost_profile toggle — enable_cost_metrics)."
  type        = bool
  default     = true
}

variable "namespace" {
  description = "Namespace to deploy into (the shared observability namespace)."
  type        = string
  default     = "observability"
}

variable "prometheus_service" {
  description = "In-cluster Prometheus service name OpenCost queries for allocation data."
  type        = string
  default     = "kube-prometheus-stack-prometheus"
}

variable "prometheus_namespace" {
  description = "Namespace of the in-cluster Prometheus service."
  type        = string
  default     = "observability"
}

variable "prometheus_port" {
  description = "Port of the in-cluster Prometheus service."
  type        = number
  default     = 9090
}

variable "helm_repository" {
  description = "OpenCost chart repository."
  type        = string
  default     = "https://opencost.github.io/opencost-helm-chart"
}

variable "helm_chart" {
  description = "Chart name."
  type        = string
  default     = "opencost"
}

variable "helm_chart_version" {
  description = "OpenCost chart version."
  type        = string
  default     = "2.5.23"
}

variable "helm_timeout" {
  description = "Timeout for Helm operations in seconds."
  type        = number
  default     = 600
}

variable "tags" {
  description = "Tags/labels to apply."
  type        = map(string)
  default     = {}
}

variable "dashboard_datasource_uid" {
  description = "Grafana datasource uid the cost dashboard queries (the Mimir where OpenCost metrics land). ADR-091."
  type        = string
  default     = "mimir"
}

variable "prometheus_external_url" {
  description = "External Prometheus-compatible query URL for OpenCost (e.g. the hub Mimir's query ingress, for a spoke with no in-cluster Prometheus). Empty = use the in-cluster prometheus_service. ADR-091."
  type        = string
  default     = ""
}

variable "create_dashboard" {
  description = "Create the Grafana cost dashboard ConfigMap. True on a cluster that runs Grafana (the hub); false on a spoke that only emits metrics. ADR-091."
  type        = bool
  default     = true
}

variable "enable_budget_enforcer" {
  description = "Run the budget-enforcement annotator (ADR-091 Phase C): an hourly CronJob that writes over-budget teams to the cost-budget-status ConfigMap the Kyverno policy reads. Enable on the spoke that runs OpenCost + the Team CRD (preprod)."
  type        = bool
  default     = false
}

variable "budget_enforcer_schedule" {
  description = "Cron schedule for the budget-enforcement annotator (ADR-091 Phase C). Cost is slow-moving — hourly is plenty."
  type        = string
  default     = "17 * * * *"
}

variable "budget_enforcer_image" {
  description = "Image for the budget-enforcement annotator (needs kubectl + curl + jq). ADR-091 Phase C."
  type        = string
  default     = "alpine/k8s:1.31.1"
}

# ---------------------------------------------------------------------------
# True cloud cost — CUR via Athena, cross-account (#668 Phase 2a/3)
# ---------------------------------------------------------------------------

variable "cluster_name" {
  description = "EKS cluster name — required when enable_cloud_cost (Pod Identity association target)."
  type        = string
  default     = ""
}

variable "enable_cloud_cost" {
  description = "Wire OpenCost's cloudCost pipeline (in-app only — its data isn't Prometheus-scrapeable, see the true-cost-exporter below) plus the true-cost-exporter to the mgmt-account CUR via Athena, cross-account AssumeRole + Pod Identity. #668 Phase 2a/3. Opt-in, default off."
  type        = bool
  default     = false
}

variable "cost_reader_role_arn" {
  description = "ARN of the mgmt-account cost_reader role (aws/cost-export module) this module's Pod-Identity roles assume cross-account for Athena/Glue/S3 CUR read access. Required when enable_cloud_cost."
  type        = string
  default     = ""
}

variable "cur_athena_results_bucket" {
  description = "S3 URI (s3://bucket/prefix/) Athena writes QUERY RESULTS to — not the CUR data bucket itself (that's implicit in the Glue table). Required when enable_cloud_cost."
  type        = string
  default     = ""
}

variable "cur_athena_region" {
  description = "AWS region the CUR Glue database/Athena workgroup live in (CUR is us-east-1 only)."
  type        = string
  default     = "us-east-1"
}

variable "cur_athena_database" {
  description = "Glue database holding the crawled CUR table. Required when enable_cloud_cost."
  type        = string
  default     = ""
}

variable "cur_athena_table" {
  description = "Glue table name for the crawled CUR data. Crawler-discovered, not Terraform-managed — confirm once via the Glue catalog (docs/runbooks/cost-true-spend.md) and set explicitly. Required when enable_cloud_cost."
  type        = string
  default     = ""
}

variable "cur_athena_workgroup" {
  description = "Athena workgroup for CUR queries. Required when enable_cloud_cost."
  type        = string
  default     = ""
}

variable "cur_account_id" {
  description = "AWS account ID the CUR covers (the payer/mgmt account) — OpenCost's AthenaConfiguration.account field. Required when enable_cloud_cost."
  type        = string
  default     = ""
}

variable "true_cost_exporter_image" {
  description = "Image for the true-cost-exporter (needs python3 + pip; boto3 is installed at container start via an init container). #668 Phase 3."
  type        = string
  default     = "python:3.12-alpine"
}

variable "true_cost_exporter_refresh_seconds" {
  description = "How often the true-cost-exporter re-queries Athena. CUR data itself has ~24h lag, so this doesn't need to be frequent."
  type        = number
  default     = 21600 # 6h
}
