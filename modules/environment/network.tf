data "azurerm_client_config" "current" {}

locals {
  location            = "westeurope"
  resource_group_name = "rg-mechmaster-${var.environment}"
  name                = "mechmaster-${var.environment}"
  suffix              = substr(sha256(data.azurerm_client_config.current.subscription_id), 0, 12)
  tags                = { project = "mechmaster", environment = var.environment, managedBy = "terraform" }
  registry_id         = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/rg-mechmaster-shared/providers/Microsoft.ContainerRegistry/registries/acrmmt${local.suffix}"
}

resource "azurerm_virtual_network" "environment" {
  name                = "vnet-${local.name}"
  location            = local.location
  resource_group_name = local.resource_group_name
  address_space       = [var.address_space]
  tags                = local.tags
}

resource "azurerm_subnet" "apps" {
  name                 = "snet-apps"
  resource_group_name  = local.resource_group_name
  virtual_network_name = azurerm_virtual_network.environment.name
  address_prefixes     = [cidrsubnet(var.address_space, 3, 0)]

  delegation {
    name = "container-apps"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_subnet" "postgres" {
  name                 = "snet-postgres"
  resource_group_name  = local.resource_group_name
  virtual_network_name = azurerm_virtual_network.environment.name
  address_prefixes     = [cidrsubnet(var.address_space, 4, 2)]

  delegation {
    name = "postgres-flexible"
    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_private_dns_zone" "postgres" {
  name                = "${local.name}.postgres.database.azure.com"
  resource_group_name = local.resource_group_name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                  = "link-${local.name}"
  resource_group_name   = local.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  virtual_network_id    = azurerm_virtual_network.environment.id
  registration_enabled  = false
}
