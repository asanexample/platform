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

# Per-team dashboard folders — every team-scoped dashboard (overview + product observability) lands in
# "Team: <team>" instead of one shared flat folder, so a team's own dashboards are all in one place. Soft
# organization only: no per-user datasource/folder ACL exists here (#590 read isolation is the
# hard-enforcement variant, a separate mechanism), any team can still browse another team's folder.
locals {
  team_folder = { for t in var.team_overview_teams : t => "Team: ${t}" }
}

# Per-team overview dashboards (one per team in `team_overview_teams`) — each pre-filtered to that team's
# environment namespaces (`<team>-*`), rendered from dashboards/team-overview.json.tmpl. A team opens its
# own "Team Overview — <team>" for a default view of only its workloads (soft: teams can still open others).
resource "kubernetes_config_map_v1" "team_dashboards" {
  for_each = local.create ? toset(var.team_overview_teams) : toset([])

  metadata {
    name        = "obs-dashboard-team-overview-${each.value}"
    namespace   = kubernetes_namespace_v1.this[0].metadata[0].name
    labels      = merge(local.k8s_labels, { grafana_dashboard = "1" })
    annotations = { grafana_folder = local.team_folder[each.value] }
  }
  data = {
    "team-overview-${each.value}.json" = replace(
      file("${path.module}/dashboards/team-overview.json.tmpl"),
      "__TEAM__", each.value
    )
  }
}

# Per-team Product Observability (one per team in `team_overview_teams`, not per-product — the Product/Stage
# picker inside covers every product the team owns, so the dashboard count doesn't grow with the product
# catalog). Rendered from dashboards/product-observability.json.tmpl, landing in the SAME per-team folder as
# the team overview above. Deliberately per-team rather than one cross-team dashboard with a Team picker too
# (an earlier iteration) — a Grafana dashboard belongs to exactly one folder, so "each team's folder has its
# own product dashboard" requires one instance per team either way.
resource "kubernetes_config_map_v1" "team_product_dashboards" {
  for_each = local.create ? toset(var.team_overview_teams) : toset([])

  metadata {
    name        = "obs-dashboard-product-observability-${each.value}"
    namespace   = kubernetes_namespace_v1.this[0].metadata[0].name
    labels      = merge(local.k8s_labels, { grafana_dashboard = "1" })
    annotations = { grafana_folder = local.team_folder[each.value] }
  }
  data = {
    "product-observability-${each.value}.json" = replace(
      file("${path.module}/dashboards/product-observability.json.tmpl"),
      "__TEAM__", each.value
    )
  }
}
