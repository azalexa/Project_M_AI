resource "azurerm_postgresql_flexible_server" "database" {
  name                          = "pg-${local.name}-${local.suffix}"
  location                      = local.location
  resource_group_name           = local.resource_group_name
  delegated_subnet_id           = azurerm_subnet.postgres.id
  private_dns_zone_id           = azurerm_private_dns_zone.postgres.id
  public_network_access_enabled = false
  sku_name                      = var.postgres_sku
  version                       = "16"
  storage_mb                    = 32768
  auto_grow_enabled             = false
  backup_retention_days         = 7
  geo_redundant_backup_enabled  = false
  tags                          = local.tags

  authentication {
    active_directory_auth_enabled = true
    password_auth_enabled         = false
    tenant_id                     = data.azurerm_client_config.current.tenant_id
  }

  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgres]

  lifecycle {
    ignore_changes = [zone]
  }
}

resource "azurerm_postgresql_flexible_server_active_directory_administrator" "admin" {
  server_name         = azurerm_postgresql_flexible_server.database.name
  resource_group_name = local.resource_group_name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  object_id           = var.database_admin.object_id
  principal_name      = var.database_admin.principal_name
  principal_type      = var.database_admin.principal_type

  lifecycle {
    ignore_changes = [principal_name]
  }
}

resource "azurerm_postgresql_flexible_server_configuration" "extensions" {
  name      = "azure.extensions"
  server_id = azurerm_postgresql_flexible_server.database.id
  value     = "POSTGIS"
}

resource "azurerm_postgresql_flexible_server_database" "mechmaster" {
  name      = "mechmaster"
  server_id = azurerm_postgresql_flexible_server.database.id
  charset   = "UTF8"
  collation = "en_US.utf8"

  depends_on = [azurerm_postgresql_flexible_server_active_directory_administrator.admin]
}
