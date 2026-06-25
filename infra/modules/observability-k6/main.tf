locals {
  create = var.create

  k8s_labels = {
    for k, v in var.tags :
    replace(lower(k), "/[^a-z0-9_.-]/", "_") => replace(lower(v), "/[^a-z0-9_.-]/", "_")
    if length(replace(lower(k), "/[^a-z0-9_.-]/", "_")) <= 63 && length(replace(lower(v), "/[^a-z0-9_.-]/", "_")) <= 63
  }
}

# ---------------------------------------------------------------------------
# k6 script (ConfigMap)
# ---------------------------------------------------------------------------

resource "kubernetes_config_map_v1" "script" {
  count = local.create ? 1 : 0

  metadata {
    name      = "k6-checks"
    namespace = var.namespace
    labels    = local.k8s_labels
  }

  data = {
    "checks.js" = file("${path.module}/scripts/checks.js")
  }
}

# ---------------------------------------------------------------------------
# k6 CronJob — runs the scripted checks on a schedule, exports metrics to Mimir via Prometheus remote_write.
# A breached threshold (checks pass-rate / latency) makes the run exit non-zero (a failed Job, visible +
# alertable). In-cluster targets, so the observability default-deny-ingress + allow-intra-namespace suffice.
# ---------------------------------------------------------------------------

resource "kubernetes_cron_job_v1" "k6" {
  count = local.create ? 1 : 0

  metadata {
    name      = "k6-synthetics"
    namespace = var.namespace
    labels    = local.k8s_labels
  }

  spec {
    schedule                      = var.schedule
    concurrency_policy            = "Forbid"
    successful_jobs_history_limit = 1
    failed_jobs_history_limit     = 3

    job_template {
      metadata {
        labels = local.k8s_labels
      }
      spec {
        backoff_limit = 0
        # Auto-delete finished Jobs (incl. failed) after 1h, so a transient failure — e.g. probes
        # getting connection-refused while the cluster is parked/scaled-down — doesn't leave a stale
        # Failed Job firing KubeJobFailed for days. The Kyverno cleanup policy only reaps *succeeded*
        # jobs (they carry completionTime); failed jobs have none, so they need this TTL.
        ttl_seconds_after_finished = 3600
        template {
          metadata {
            labels = merge(local.k8s_labels, { "app.kubernetes.io/name" = "k6" })
          }
          spec {
            restart_policy = "Never"

            container {
              name    = "k6"
              image   = var.k6_image
              command = ["k6", "run", "/scripts/checks.js"]

              # Prometheus remote_write output → Mimir, stamped with the tenant header.
              env {
                name  = "K6_OUT"
                value = "experimental-prometheus-rw"
              }
              env {
                name  = "K6_PROMETHEUS_RW_SERVER_URL"
                value = var.mimir_remote_write_url
              }
              env {
                name  = "K6_PROMETHEUS_RW_HTTP_HEADERS"
                value = "X-Scope-OrgID:${var.tenant_id}"
              }
              env {
                name  = "K6_PROMETHEUS_RW_TREND_STATS"
                value = "p(95),p(99),avg"
              }

              volume_mount {
                name       = "script"
                mount_path = "/scripts"
                read_only  = true
              }

              resources {
                requests = { cpu = "50m", memory = "64Mi" }
                limits   = { memory = "128Mi" }
              }
            }

            volume {
              name = "script"
              config_map {
                name = kubernetes_config_map_v1.script[0].metadata[0].name
              }
            }
          }
        }
      }
    }
  }
}
