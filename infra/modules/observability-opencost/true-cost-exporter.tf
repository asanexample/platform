# ---------------------------------------------------------------------------
# True-cost-exporter (#668 Phase 3). OpenCost's own cloudCost pipeline (wired in main.tf) is NOT
# Prometheus-scrapeable — it only serves its own /cloudCost REST API. This is the actual Grafana-visible
# fix: a small long-running exporter that queries the mgmt CUR via Athena directly (cross-account
# AssumeRole, same cost_reader role OpenCost assumes) and serves the results as Prometheus metrics.
#
# Refreshes on a timer (not per-scrape) since CUR data itself has ~24h lag — no point querying Athena
# every 30s. Read-only: SELECT-only Athena queries, no write access anywhere.
# ---------------------------------------------------------------------------

locals {
  true_cost_exporter_script = <<-PYEOF
    import boto3, os, sys, time, threading, http.server

    REGION    = os.environ["CUR_REGION"]
    DATABASE  = os.environ["CUR_DATABASE"]
    TABLE     = os.environ["CUR_TABLE"]
    WORKGROUP = os.environ["CUR_WORKGROUP"]
    RESULTS   = os.environ["CUR_RESULTS_BUCKET"]
    ROLE_ARN  = os.environ["COST_READER_ROLE_ARN"]
    REFRESH_S = int(os.environ.get("REFRESH_SECONDS", "21600"))
    METRICS_FILE = "/tmp/metrics.prom"

    MONTH_FILTER = "CAST(bill_billing_period_start_date AS DATE) = DATE_TRUNC('month', CURRENT_DATE)"

    QUERIES = {
        "team":    f"SELECT COALESCE(resource_tags_user_team, 'untagged') AS label, SUM(line_item_unblended_cost) AS cost FROM {DATABASE}.{TABLE} WHERE {MONTH_FILTER} GROUP BY 1",
        "service": f"SELECT product_servicecode AS label, SUM(line_item_unblended_cost) AS cost FROM {DATABASE}.{TABLE} WHERE {MONTH_FILTER} GROUP BY 1 HAVING SUM(line_item_unblended_cost) > 0.01",
        "account": f"SELECT line_item_usage_account_id AS label, SUM(line_item_unblended_cost) AS cost FROM {DATABASE}.{TABLE} WHERE {MONTH_FILTER} GROUP BY 1",
    }
    # 2-column shape (label, cost) to match run_query()'s generic row parsing — a bare 1-column SELECT
    # caused an IndexError live (#668): Athena returns only one field, but run_query always reads data[1].
    COMPUTE_QUERY = f"SELECT 'compute' AS label, SUM(line_item_unblended_cost) AS cost FROM {DATABASE}.{TABLE} WHERE {MONTH_FILTER} AND product_servicecode = 'AmazonEC2'"

    def athena_client():
        sts = boto3.client("sts", region_name=REGION)
        creds = sts.assume_role(RoleArn=ROLE_ARN, RoleSessionName="true-cost-exporter")["Credentials"]
        return boto3.client(
            "athena", region_name=REGION,
            aws_access_key_id=creds["AccessKeyId"],
            aws_secret_access_key=creds["SecretAccessKey"],
            aws_session_token=creds["SessionToken"],
        )

    def run_query(client, sql):
        qid = client.start_query_execution(
            QueryString=sql, WorkGroup=WORKGROUP,
            ResultConfiguration={"OutputLocation": RESULTS},
        )["QueryExecutionId"]
        state = "RUNNING"
        for _ in range(60):
            state = client.get_query_execution(QueryExecutionId=qid)["QueryExecution"]["Status"]["State"]
            if state in ("SUCCEEDED", "FAILED", "CANCELLED"):
                break
            time.sleep(2)
        if state != "SUCCEEDED":
            raise RuntimeError(f"Athena query did not succeed: {state}")
        rows = []
        first = True
        for page in client.get_paginator("get_query_results").paginate(QueryExecutionId=qid):
            for row in page["ResultSet"]["Rows"]:
                if first:
                    first = False
                    continue
                data = row["Data"]
                label = data[0].get("VarCharValue", "") or "unknown"
                cost = float(data[1].get("VarCharValue", "0") or 0)
                rows.append((label, cost))
        return rows

    def esc(v):
        # Realistic CUR label values (team names, AWS service codes, account IDs) never contain a quote
        # or newline; strip rather than escape to avoid double-escaping headaches in this heredoc.
        return v.replace('"', "").replace("\n", "")

    def refresh():
        client = athena_client()
        lines, team_total = [], 0.0
        for breakdown, sql in QUERIES.items():
            try:
                rows = run_query(client, sql)
            except Exception as e:
                print(f"query {breakdown} failed: {e}", file=sys.stderr)
                continue
            for label, cost in rows:
                lines.append(f'platform_true_cost_monthly_usd{{breakdown="{breakdown}",label="{esc(label)}"}} {cost}')
                if breakdown == "team":
                    team_total += cost

        compute_total = None
        try:
            rows = run_query(client, COMPUTE_QUERY)
            compute_total = rows[0][1] if rows else 0.0
        except Exception as e:
            print(f"compute query failed: {e}", file=sys.stderr)

        out = [
            "# HELP platform_true_cost_monthly_usd Actual AWS spend (CUR unblended cost) for the current billing month, by breakdown dimension.",
            "# TYPE platform_true_cost_monthly_usd gauge",
            *lines,
            "# HELP platform_true_cost_monthly_usd_total Actual AWS spend for the current billing month, all teams.",
            "# TYPE platform_true_cost_monthly_usd_total gauge",
            f"platform_true_cost_monthly_usd_total {team_total}",
        ]
        if compute_total is not None:
            out += [
                "# HELP platform_true_cost_compute_monthly_usd_total EC2 spend for the current billing month — reconcile against OpenCost's in-cluster node-price estimate.",
                "# TYPE platform_true_cost_compute_monthly_usd_total gauge",
                f"platform_true_cost_compute_monthly_usd_total {compute_total}",
            ]
        out += [
            "# HELP platform_true_cost_exporter_last_success_timestamp_seconds Unix time of the last successful Athena refresh.",
            "# TYPE platform_true_cost_exporter_last_success_timestamp_seconds gauge",
            f"platform_true_cost_exporter_last_success_timestamp_seconds {int(time.time())}",
        ]
        tmp = METRICS_FILE + ".tmp"
        with open(tmp, "w") as f:
            f.write("\n".join(out) + "\n")
        os.replace(tmp, METRICS_FILE)
        print(f"refreshed: {len(lines)} series, team total USD {team_total:.2f}")

    def refresh_loop():
        while True:
            try:
                refresh()
            except Exception as e:
                print(f"refresh failed: {e}", file=sys.stderr)
            time.sleep(REFRESH_S)

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path != "/metrics":
                self.send_response(404)
                self.end_headers()
                return
            try:
                with open(METRICS_FILE, "rb") as f:
                    body = f.read()
            except FileNotFoundError:
                body = b"# not yet refreshed\n"
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; version=0.0.4")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, fmt, *args):
            pass

    if __name__ == "__main__":
        threading.Thread(target=refresh_loop, daemon=True).start()
        http.server.HTTPServer(("0.0.0.0", 9105), Handler).serve_forever()
  PYEOF
}

resource "kubernetes_config_map_v1" "true_cost_exporter_script" {
  count = local.enable_cloud_cost ? 1 : 0

  metadata {
    name      = "true-cost-exporter-script"
    namespace = var.namespace
  }
  data = {
    "exporter.py" = local.true_cost_exporter_script
  }
}

resource "kubernetes_service_account_v1" "true_cost_exporter" {
  count = local.enable_cloud_cost ? 1 : 0

  metadata {
    name      = "true-cost-exporter"
    namespace = var.namespace
  }
}

resource "kubernetes_deployment_v1" "true_cost_exporter" {
  count = local.enable_cloud_cost ? 1 : 0

  metadata {
    name      = "true-cost-exporter"
    namespace = var.namespace
    labels    = { app = "true-cost-exporter" }
  }

  spec {
    replicas = 1
    selector {
      match_labels = { app = "true-cost-exporter" }
    }
    template {
      metadata {
        labels = { app = "true-cost-exporter" }
      }
      spec {
        service_account_name = kubernetes_service_account_v1.true_cost_exporter[0].metadata[0].name
        security_context {
          run_as_non_root = true
          run_as_user     = 65532
          seccomp_profile { type = "RuntimeDefault" }
        }

        # boto3 isn't in the base python image and read_only_root_filesystem blocks a runtime `pip install`
        # in the main container — install into a shared emptyDir instead, keeping the serving container's
        # root filesystem read-only.
        init_container {
          name    = "install-deps"
          image   = var.true_cost_exporter_image
          command = ["pip", "install", "--no-cache-dir", "--target=/deps", "boto3"]
          volume_mount {
            name       = "deps"
            mount_path = "/deps"
          }
          security_context {
            allow_privilege_escalation = false
            capabilities { drop = ["ALL"] }
          }
        }

        container {
          name  = "exporter"
          image = var.true_cost_exporter_image
          # -u: unbuffered stdout — without it, python3's stdout is fully block-buffered when not a tty
          # (confirmed live, #668: refresh()'s print()s never appeared in `kubectl logs` even though the
          # exporter was working correctly — only visible by exec-ing into the container).
          command = ["python3", "-u", "/app/exporter.py"]

          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            capabilities { drop = ["ALL"] }
          }
          resources {
            requests = { cpu = "10m", memory = "48Mi" }
            limits   = { memory = "192Mi" }
          }

          env {
            name  = "PYTHONPATH"
            value = "/deps"
          }
          env {
            name  = "CUR_REGION"
            value = var.cur_athena_region
          }
          env {
            name  = "CUR_DATABASE"
            value = var.cur_athena_database
          }
          env {
            name  = "CUR_TABLE"
            value = var.cur_athena_table
          }
          env {
            name  = "CUR_WORKGROUP"
            value = var.cur_athena_workgroup
          }
          env {
            name  = "CUR_RESULTS_BUCKET"
            value = var.cur_athena_results_bucket
          }
          env {
            name  = "COST_READER_ROLE_ARN"
            value = var.cost_reader_role_arn
          }
          env {
            name  = "REFRESH_SECONDS"
            value = tostring(var.true_cost_exporter_refresh_seconds)
          }

          port {
            container_port = 9105
            name           = "metrics"
          }

          volume_mount {
            name       = "deps"
            mount_path = "/deps"
          }
          volume_mount {
            name       = "script"
            mount_path = "/app"
          }
          volume_mount {
            name       = "tmp"
            mount_path = "/tmp"
          }

          readiness_probe {
            http_get {
              path = "/metrics"
              port = 9105
            }
            initial_delay_seconds = 10
            period_seconds        = 30
          }
          liveness_probe {
            http_get {
              path = "/metrics"
              port = 9105
            }
            initial_delay_seconds = 30
            period_seconds        = 60
          }
        }

        volume {
          name = "deps"
          empty_dir {}
        }
        volume {
          name = "tmp"
          empty_dir {}
        }
        volume {
          name = "script"
          config_map {
            name = kubernetes_config_map_v1.true_cost_exporter_script[0].metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "true_cost_exporter" {
  count = local.enable_cloud_cost ? 1 : 0

  metadata {
    name      = "true-cost-exporter"
    namespace = var.namespace
    labels    = { app = "true-cost-exporter" }
  }
  spec {
    selector = { app = "true-cost-exporter" }
    port {
      name        = "metrics"
      port        = 9105
      target_port = 9105
    }
  }
}

# ServiceMonitor CRD ships with the kube-prometheus-stack chart (already installed), so kubernetes_manifest
# is fine here (no CRD-at-plan-time ordering issue) — same pattern as observability-blackbox's Probe.
resource "kubernetes_manifest" "true_cost_exporter_service_monitor" {
  count = local.enable_cloud_cost ? 1 : 0

  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "true-cost-exporter"
      namespace = var.namespace
    }
    spec = {
      selector = {
        matchLabels = { app = "true-cost-exporter" }
      }
      endpoints = [{
        port     = "metrics"
        path     = "/metrics"
        interval = "5m"
      }]
    }
  }

  depends_on = [kubernetes_service_v1.true_cost_exporter]
}
