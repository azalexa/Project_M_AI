resource "azurerm_user_assigned_identity" "app" {
  name                = "id-${local.name}-api"
  location            = local.location
  resource_group_name = local.resource_group_name
  tags                = local.tags
}

resource "azurerm_storage_account" "files" {
  name                            = "stmmt${var.environment}${local.suffix}"
  location                        = local.location
  resource_group_name             = local.resource_group_name
  account_kind                    = "StorageV2"
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  access_tier                     = "Hot"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true
  tags                            = local.tags

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 14
    }

    container_delete_retention_policy {
      days = 14
    }
  }
}

resource "azurerm_storage_container" "files" {
  name                  = "files"
  storage_account_id    = azurerm_storage_account.files.id
  container_access_type = "private"
}

resource "azurerm_role_assignment" "files" {
  scope                = azurerm_storage_container.files.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "registry" {
  scope                = local.registry_id
  role_definition_name = "Container Registry Repository Reader"
  condition_version    = "2.0"
  condition            = "@Request[Microsoft.ContainerRegistry/registries/repositories:name] StringEqualsIgnoreCase 'mechmaster/${var.environment}-api'"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_key_vault" "environment" {
  name                       = "kv-mmt-${var.environment}-${local.suffix}"
  resource_group_name        = local.resource_group_name
  location                   = local.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  purge_protection_enabled   = true
  soft_delete_retention_days = 7
  tags                       = local.tags
}

resource "azurerm_role_assignment" "vault" {
  scope                = azurerm_key_vault.environment.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_static_web_app" "frontend" {
  name                = "swa-${local.name}-${local.suffix}"
  resource_group_name = local.resource_group_name
  location            = local.location
  sku_tier            = var.static_site_sku
  sku_size            = var.static_site_sku
  tags                = local.tags
}

resource "azurerm_container_app_environment" "apps" {
  name                       = "cae-${local.name}"
  location                   = local.location
  resource_group_name        = local.resource_group_name
  infrastructure_subnet_id   = azurerm_subnet.apps.id
  log_analytics_workspace_id = try(azurerm_log_analytics_workspace.prod[0].id, null)
  tags                       = local.tags

  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }
}

resource "azurerm_container_app" "api" {
  name                         = "ca-${local.name}-api"
  container_app_environment_id = azurerm_container_app_environment.apps.id
  resource_group_name          = local.resource_group_name
  workload_profile_name        = "Consumption"
  revision_mode                = "Single"
  tags                         = local.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.app.id]
  }

  registry {
    server   = "acrmmt${local.suffix}.azurecr.io"
    identity = azurerm_user_assigned_identity.app.id
  }

  ingress {
    external_enabled           = true
    allow_insecure_connections = false
    target_port                = 8080
    transport                  = "auto"

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = var.min_replicas
    max_replicas = var.environment == "prod" ? 3 : 2
    container {
      name   = "api"
      image  = "nginxinc/nginx-unprivileged:stable-alpine"
      cpu    = 0.5
      memory = "1Gi"

      env {
        name  = "MECHMASTER_ENVIRONMENT"
        value = var.environment
      }
      env {
        name  = "POSTGRES_HOST"
        value = azurerm_postgresql_flexible_server.database.fqdn
      }
      env {
        name  = "AZURE_CLIENT_ID"
        value = azurerm_user_assigned_identity.app.client_id
      }
      env {
        name  = "STORAGE_ACCOUNT_URL"
        value = azurerm_storage_account.files.primary_blob_endpoint
      }
    }
  }

  depends_on = [azurerm_role_assignment.registry]

  lifecycle {
    ignore_changes = [template[0].container[0].image]
  }
}

output "deployment" {
  value = {
    api_url       = "https://${azurerm_container_app.api.ingress[0].fqdn}"
    postgres_host = azurerm_postgresql_flexible_server.database.fqdn
    postgres_name = azurerm_postgresql_flexible_server.database.name
    frontend_host = azurerm_static_web_app.frontend.default_host_name
    storage_name  = azurerm_storage_account.files.name
    identity_name = azurerm_user_assigned_identity.app.name
    identity_id   = azurerm_user_assigned_identity.app.principal_id
  }
}
