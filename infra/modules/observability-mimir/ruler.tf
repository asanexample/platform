# ---------------------------------------------------------------------------
# Ruler rules-sync (P4, ADR-082) — load the curated spoke alert rules into the ruler PER TENANT, so a spoke's
# remote-written metrics produce alerts that reach the hub Alertmanager → the triage agent. The ConfigMap is the
# source of truth; a mimirtool `rules sync` CronJob reconciles each tenant's ruler to match it (add/update/delete)
# every var.ruler_rules_sync_schedule — self-healing + IaC-managed, replacing any hand-loaded rules. Gated on
# enable_ruler + a non-empty ruler_tenants. (observability is an infra ns — exempt from env-scoped Kyverno, so the
# docker.io/grafana mimirtool image is fine.)
# ---------------------------------------------------------------------------

resource "kubernetes_config_map_v1" "ruler_rules" {
  count = local.create && var.enable_ruler ? 1 : 0

  metadata {
    name      = "${var.helm_release_name}-ruler-rules"
    namespace = var.namespace
  }
  # Each file becomes a Mimir ruler namespace (mimirtool keys on the filename). The curated static rules plus —
  # when any per-app SLOs are declared — a generated `app-slos.yaml` namespace (ADR-056 per-app SLOs / W11).
  data = merge(
    { for f in fileset("${path.module}/files/ruler", "*.yaml") : f => file("${path.module}/files/ruler/${f}") },
    length(var.app_slos) > 0 ? {
      # Enrich each SLO with cleanly-formatted budget/objective ratios (raw `1 - 99.9/100` renders as an ugly
      # long float); `%g` gives the shortest exact form (0.001) that PromQL parses.
      "app-slos.yaml" = templatefile("${path.module}/templates/app-slo-rules.yaml.tftpl", {
        slos = [for s in var.app_slos : merge(s, {
          error_budget    = format("%g", 1 - s.objective / 100)
          objective_ratio = format("%g", s.objective / 100)
        })]
      })
    } : {},
    var.spoke_metrics_freshness.enabled ? {
      # "Who watches the watcher": a dead spoke shows zero errors under availability-only SLOs. Evaluated
      # inside each ruler tenant, since `up`'s own last-received timestamp only exists in that tenant's
      # remote-written data, not the hub's local scrape.
      "spoke-freshness.yaml" = templatefile("${path.module}/templates/spoke-freshness-rules.yaml.tftpl", {
        warning_stale_after_seconds  = var.spoke_metrics_freshness.warning_stale_after_seconds
        critical_stale_after_seconds = var.spoke_metrics_freshness.critical_stale_after_seconds
      })
    } : {},
  )
}

resource "kubernetes_cron_job_v1" "ruler_rules_sync" {
  # One CronJob per tenant: the grafana/mimirtool image is distroless (no shell), so we can't loop in a script —
  # run the mimirtool entrypoint directly with a fixed --id instead.
  for_each = local.create && var.enable_ruler ? toset(var.ruler_tenants) : toset([])

  metadata {
    name      = "${var.helm_release_name}-ruler-rules-sync-${each.value}"
    namespace = var.namespace
  }
  spec {
    schedule                      = var.ruler_rules_sync_schedule
    concurrency_policy            = "Forbid"
    successful_jobs_history_limit = 1
    failed_jobs_history_limit     = 2
    starting_deadline_seconds     = 120

    job_template {
      metadata {
        labels = { "app.kubernetes.io/name" = var.helm_release_name, "app.kubernetes.io/component" = "ruler-rules-sync" }
      }
      spec {
        backoff_limit = 2
        template {
          metadata {
            labels = { "app.kubernetes.io/name" = var.helm_release_name, "app.kubernetes.io/component" = "ruler-rules-sync" }
          }
          spec {
            restart_policy                  = "Never"
            automount_service_account_token = false

            security_context {
              run_as_non_root = true
              run_as_user     = 10001
              seccomp_profile { type = "RuntimeDefault" }
            }

            # Wait for the ruler API before the (distroless, no-retry) mimirtool runs. Without this, a one-shot
            # sync that lands in the post-unpark window — nodes back but the gateway/ruler still starting — gets
            # `connection refused` and the whole job fails (the failures we saw). Poll the exact endpoint the
            # sync uses, bounded to ~5m so a full park (API absent) fails fast instead of blocking the 15m schedule.
            init_container {
              name  = "wait-for-ruler-api"
              image = "curlimages/curl:8.11.1"
              command = ["sh", "-c", <<-SH
                i=0
                until curl -sf -H "X-Scope-OrgID: ${each.value}" "http://${var.helm_release_name}-gateway.${var.namespace}.svc/prometheus/config/v1/rules" -o /dev/null; do
                  i=$((i + 1)); [ "$i" -ge 30 ] && echo "ruler API not ready after 5m; giving up" && exit 1
                  echo "waiting for mimir ruler API ($i/30)..."; sleep 10
                done
                echo "mimir ruler API ready"
              SH
              ]
              resources {
                requests = { cpu = "10m", memory = "16Mi" }
                limits   = { cpu = "100m", memory = "32Mi" }
              }
              security_context {
                allow_privilege_escalation = false
                read_only_root_filesystem  = true
                capabilities { drop = ["ALL"] }
              }
            }

            container {
              name  = "mimirtool"
              image = "grafana/mimirtool:${var.mimirtool_version}"
              # `rules sync` reconciles THIS tenant's ruler to match the mounted rule files (add/update AND delete,
              # so a removed rule is removed). The cluster label rides through from remote-write, so fired alerts
              # self-route to the tenant (ADR-082 Phase 2). Files are listed explicitly (no shell glob).
              args = concat(
                ["rules", "sync", "--address", "http://${var.helm_release_name}-gateway.${var.namespace}.svc", "--id", each.value],
                [for f in fileset("${path.module}/files/ruler", "*.yaml") : "/rules/${f}"],
                # The generated per-app SLO namespace isn't a static file — list it explicitly when present.
                length(var.app_slos) > 0 ? ["/rules/app-slos.yaml"] : [],
                var.spoke_metrics_freshness.enabled ? ["/rules/spoke-freshness.yaml"] : [],
              )
              resources {
                requests = { cpu = "10m", memory = "32Mi" }
                limits   = { cpu = "200m", memory = "128Mi" }
              }
              security_context {
                allow_privilege_escalation = false
                capabilities { drop = ["ALL"] }
              }
              volume_mount {
                name       = "rules"
                mount_path = "/rules"
                read_only  = true
              }
            }
            volume {
              name = "rules"
              config_map { name = kubernetes_config_map_v1.ruler_rules[0].metadata[0].name }
            }
          }
        }
      }
    }
  }
}
