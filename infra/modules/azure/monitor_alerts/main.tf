resource "azurerm_monitor_action_group" "this" {
  for_each = var.create ? var.action_groups : {}

  name                = "${each.key}-${var.workload}-${var.environment}-${var.region_abbv}"
  resource_group_name = var.resource_group_name
  short_name          = each.value.short_name
  enabled             = each.value.enabled

  dynamic "email_receiver" {
    for_each = each.value.email_receivers
    content {
      name                    = email_receiver.value.name
      email_address           = email_receiver.value.email_address
      use_common_alert_schema = email_receiver.value.use_common_alert_schema
    }
  }

  dynamic "webhook_receiver" {
    for_each = each.value.webhook_receivers
    content {
      name                    = webhook_receiver.value.name
      service_uri             = webhook_receiver.value.service_uri
      use_common_alert_schema = webhook_receiver.value.use_common_alert_schema
    }
  }

  tags = var.tags
}

resource "azurerm_monitor_metric_alert" "this" {
  for_each = var.create ? var.metric_alerts : {}

  name                = "${each.key}-${var.workload}-${var.environment}-${var.region_abbv}"
  resource_group_name = var.resource_group_name
  description         = each.value.description
  severity            = each.value.severity
  enabled             = each.value.enabled
  scopes              = each.value.scopes
  frequency           = each.value.frequency
  window_size         = each.value.window_size
  auto_mitigate       = each.value.auto_mitigate

  dynamic "criteria" {
    for_each = each.value.criteria
    content {
      metric_namespace = criteria.value.metric_namespace
      metric_name      = criteria.value.metric_name
      aggregation      = criteria.value.aggregation
      operator         = criteria.value.operator
      threshold        = criteria.value.threshold

      dynamic "dimension" {
        for_each = criteria.value.dimension
        content {
          name     = dimension.value.name
          operator = dimension.value.operator
          values   = dimension.value.values
        }
      }
    }
  }

  dynamic "action" {
    for_each = each.value.action_group_keys
    content {
      action_group_id = azurerm_monitor_action_group.this[action.value].id
    }
  }

  tags = var.tags
}

resource "azurerm_monitor_activity_log_alert" "this" {
  for_each = var.create ? var.activity_log_alerts : {}

  name                = "${each.key}-${var.workload}-${var.environment}-${var.region_abbv}"
  resource_group_name = var.resource_group_name
  location            = "global"
  description         = each.value.description
  enabled             = each.value.enabled
  scopes              = each.value.scopes

  criteria {
    category       = each.value.criteria.category
    operation_name = each.value.criteria.operation_name
    level          = each.value.criteria.level
    status         = each.value.criteria.status
    resource_type  = each.value.criteria.resource_type

    dynamic "service_health" {
      for_each = each.value.criteria.service_health != null ? [each.value.criteria.service_health] : []
      content {
        events   = service_health.value.events
        locations = service_health.value.locations
        services  = service_health.value.services
      }
    }
  }

  dynamic "action" {
    for_each = each.value.action_group_keys
    content {
      action_group_id = azurerm_monitor_action_group.this[action.value].id
    }
  }

  tags = var.tags
}
