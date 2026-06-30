# ---------------------------------------------------------------------------
# Budget-enforcement bridge (ADR-091 Phase C, option b). On a spoke where OpenCost runs, an hourly CronJob
# queries the hub Mimir for each team's budget UTILISATION (the same spend ÷ budget the dashboard/alerts use)
# and writes the over-budget teams to the `cost-budget-status` ConfigMap. The Kyverno policy (policy module)
# reads that ConfigMap to block NEW XEnvironment provisioning for over-budget teams (audit-first, fail-open).
#
# Lives in the observability namespace because that's where Mimir egress already works (the agent uses it).
# Fail-open: a failed Mimir query leaves the ConfigMap unchanged (and an empty/all-"ok" ConfigMap never blocks).
# ---------------------------------------------------------------------------

locals {
  enforce_create = local.create && var.enable_budget_enforcer
  budget_cm_name = "cost-budget-status"
  # spend ÷ budget × 100, per team (team derived from the env-namespace prefix); >= 100 = over budget.
  budget_util_query = "100 * ( sum by (team) ( label_replace( sum by (namespace) ( (container_cpu_allocation * on(node) group_left() node_cpu_hourly_cost) + ((container_memory_allocation_bytes / 1024^3) * on(node) group_left() node_ram_hourly_cost) ) * 730, \"team\", \"$1\", \"namespace\", \"^([a-z0-9]+)-.*\" ) ) / on(team) group_left() max by (team) (team_budget_monthly_usd) )"
}

resource "kubernetes_service_account_v1" "budget_enforcer" {
  count = local.enforce_create ? 1 : 0
  metadata {
    name      = "cost-budget-enforcer"
    namespace = var.namespace
  }
}

resource "kubernetes_role_v1" "budget_enforcer" {
  count = local.enforce_create ? 1 : 0
  metadata {
    name      = "cost-budget-enforcer"
    namespace = var.namespace
  }
  rule {
    api_groups = [""]
    resources  = ["configmaps"]
    verbs      = ["get", "list", "create", "update", "patch"]
  }
}

resource "kubernetes_role_binding_v1" "budget_enforcer" {
  count = local.enforce_create ? 1 : 0
  metadata {
    name      = "cost-budget-enforcer"
    namespace = var.namespace
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.budget_enforcer[0].metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.budget_enforcer[0].metadata[0].name
    namespace = var.namespace
  }
}

# Seed an empty status ConfigMap so the Kyverno policy always has something to read (empty = all teams ok =
# fail-open). The CronJob owns the data after first run; ignore changes so we don't fight it.
resource "kubernetes_config_map_v1" "budget_status" {
  count = local.enforce_create ? 1 : 0
  metadata {
    name      = local.budget_cm_name
    namespace = var.namespace
    labels    = { "app.kubernetes.io/part-of" = "cost-guardrails", "app.kubernetes.io/managed-by" = "terraform" }
  }
  data = {}
  lifecycle {
    ignore_changes = [data]
  }
}

resource "kubernetes_cron_job_v1" "budget_enforcer" {
  count = local.enforce_create ? 1 : 0
  metadata {
    name      = "cost-budget-enforcer"
    namespace = var.namespace
  }
  spec {
    schedule                      = var.budget_enforcer_schedule
    concurrency_policy            = "Forbid"
    successful_jobs_history_limit = 1
    failed_jobs_history_limit     = 2
    job_template {
      metadata {}
      spec {
        backoff_limit = 1
        template {
          metadata {}
          spec {
            service_account_name = kubernetes_service_account_v1.budget_enforcer[0].metadata[0].name
            restart_policy       = "Never"
            security_context {
              run_as_non_root = true
              run_as_user     = 65532
              seccomp_profile { type = "RuntimeDefault" }
            }
            container {
              name  = "enforcer"
              image = var.budget_enforcer_image
              security_context {
                allow_privilege_escalation = false
                read_only_root_filesystem  = true
                capabilities { drop = ["ALL"] }
              }
              resources {
                requests = { cpu = "10m", memory = "32Mi" }
                limits   = { memory = "96Mi" }
              }
              env {
                name  = "MIMIR_QUERY_URL"
                value = "${var.prometheus_external_url}/api/v1/query"
              }
              env {
                name  = "NAMESPACE"
                value = var.namespace
              }
              env {
                name  = "CM_NAME"
                value = local.budget_cm_name
              }
              env {
                name  = "QUERY"
                value = local.budget_util_query
              }
              command = ["/bin/sh", "-c", <<-EOS
                set -uo pipefail
                resp=$(curl -sf --max-time 25 "$MIMIR_QUERY_URL" --data-urlencode "query=$QUERY") || {
                  echo "Mimir query failed — fail-open, leaving $CM_NAME unchanged"; exit 0;
                }
                # team=exceeded when utilisation >= 100, else ok. No teams/budgets => empty => all ok (fail-open).
                lits=$(echo "$resp" | jq -r '.data.result[]? | "--from-literal=" + .metric.team + "=" + (if (.value[1]|tonumber) >= 100 then "exceeded" else "ok" end)')
                # shellcheck disable=SC2086
                kubectl create configmap "$CM_NAME" -n "$NAMESPACE" $lits --dry-run=client -o yaml | kubectl apply -f -
                echo "$CM_NAME updated"
              EOS
              ]
            }
          }
        }
      }
    }
  }
  depends_on = [kubernetes_config_map_v1.budget_status]
}
