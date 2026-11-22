resource "azurerm_log_analytics_workspace" "prod" {
  count               = var.alert_email == null ? 0 : 1
  name                = "law-${local.name}-${local.suffix}"
  location            = local.location
  resource_group_name = local.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  daily_quota_gb      = 0.5
  tags                = local.tags
}

resource "azurerm_monitor_diagnostic_setting" "postgres" {
  count                      = var.alert_email == null ? 0 : 1
  name                       = "postgres-logs"
  target_resource_id         = azurerm_postgresql_flexible_server.database.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.prod[0].id

  enabled_log {
    category = "PostgreSQLLogs"
  }
}

resource "azurerm_monitor_action_group" "prod" {
  count               = var.alert_email == null ? 0 : 1
  name                = "ag-${local.name}"
  short_name          = "mmtprod"
  resource_group_name = local.resource_group_name
  location            = "global"

  email_receiver {
    name          = "operator"
    email_address = var.alert_email
  }
}

resource "azurerm_monitor_metric_alert" "postgres" {
  for_each = var.alert_email == null ? {} : {
    cpu_percent     = "Average"
    storage_percent = "Maximum"
  }

  name                = "alert-${local.name}-${each.key}"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_postgresql_flexible_server.database.id]
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"

  criteria {
    metric_namespace = "Microsoft.DBforPostgreSQL/flexibleServers"
    metric_name      = each.key
    aggregation      = each.value
    operator         = "GreaterThan"
    threshold        = 85
  }

  action {
    action_group_id = azurerm_monitor_action_group.prod[0].id
  }
}
