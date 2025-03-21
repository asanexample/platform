# Create role assignments for admin groups
resource "azurerm_role_assignment" "grafana_admin" {
  count                = length(var.admin_group_object_ids)
  scope                = azurerm_dashboard_grafana.grafana.id
  role_definition_name = "Grafana Admin"
  principal_id         = var.admin_group_object_ids[count.index]
  principal_type       = "Group"
} 