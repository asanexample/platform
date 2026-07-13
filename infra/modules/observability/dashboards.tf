# ---------------------------------------------------------------------------
# Curated dashboards-as-code — one ConfigMap per JSON in dashboards/, picked up by the
# Grafana sidecar (label grafana_dashboard=1). Tier-1 bundled dashboards ship with the chart;
# these are the tier-3 custom (Platform Health) + tier-2 vendored ones.
# ---------------------------------------------------------------------------
resource "kubernetes_config_map_v1" "dashboards" {
  for_each = local.create ? fileset("${path.module}/dashboards", "*.json") : toset([])

  metadata {
    name        = "obs-dashboard-${trimsuffix(each.value, ".json")}"
    namespace   = kubernetes_namespace_v1.this[0].metadata[0].name
    labels      = merge(local.k8s_labels, { grafana_dashboard = "1" })
    annotations = { grafana_folder = "Platform" }
  }
  data = {
    (each.value) = file("${path.module}/dashboards/${each.value}")
  }
}

# Per-team overview dashboards (one per team in `team_overview_teams`) — each pre-filtered to that team's
# environment namespaces (`<team>-*`), rendered from dashboards/team-overview.json.tmpl. A team opens its
# own "Team Overview — <team>" (Teams folder) for a default view of only its workloads (soft: teams can
# still open others). Team-specific dashboards, no per-user datasource gating (#590 read isolation is the
# hard-enforcement variant; this is the lightweight default-view need).
resource "kubernetes_config_map_v1" "team_dashboards" {
  for_each = local.create ? toset(var.team_overview_teams) : toset([])

  metadata {
    name        = "obs-dashboard-team-overview-${each.value}"
    namespace   = kubernetes_namespace_v1.this[0].metadata[0].name
    labels      = merge(local.k8s_labels, { grafana_dashboard = "1" })
    annotations = { grafana_folder = "Teams" }
  }
  data = {
    "team-overview-${each.value}.json" = replace(
      file("${path.module}/dashboards/team-overview.json.tmpl"),
      "__TEAM__", each.value
    )
  }
}
