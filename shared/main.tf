data "azurerm_client_config" "current" {}

locals {
  registry_name = "acrmmt${substr(sha256(data.azurerm_client_config.current.subscription_id), 0, 12)}"
}

resource "azurerm_resource_group" "project" {
  for_each = toset(["shared", "dev", "prod"])
  name     = "rg-mechmaster-${each.key}"
  location = "westeurope"
  tags     = { project = "mechmaster", environment = each.key, managedBy = "terraform" }
}

resource "azurerm_container_registry" "shared" {
  name                                         = local.registry_name
  resource_group_name                          = azurerm_resource_group.project["shared"].name
  location                                     = azurerm_resource_group.project["shared"].location
  sku                                          = "Basic"
  admin_enabled                                = false
  role_assignment_mode                         = "AbacRepositoryPermissions"
  azuread_authentication_as_arm_policy_enabled = true
  tags                                         = azurerm_resource_group.project["shared"].tags
}

resource "azurerm_consumption_budget_resource_group" "project" {
  for_each          = azurerm_resource_group.project
  name              = "budget-mechmaster-${each.key}"
  resource_group_id = each.value.id
  amount            = var.monthly_budgets[each.key]
  time_grain        = "Monthly"

  time_period {
    start_date = var.budget_start
  }

  dynamic "notification" {
    for_each = toset([80, 100])
    content {
      enabled        = true
      threshold      = notification.value
      operator       = "GreaterThanOrEqualTo"
      threshold_type = "Actual"
      contact_emails = [var.alert_email]
    }
  }
}

resource "azurerm_user_assigned_identity" "pipeline" {
  for_each            = var.github_oidc_subjects
  name                = "id-mechmaster-ci-${each.key}"
  resource_group_name = azurerm_resource_group.project["shared"].name
  location            = azurerm_resource_group.project["shared"].location
}

resource "azurerm_federated_identity_credential" "pipeline" {
  for_each            = azurerm_user_assigned_identity.pipeline
  name                = "github-${each.key}"
  resource_group_name = azurerm_resource_group.project["shared"].name
  parent_id           = each.value.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = "https://token.actions.githubusercontent.com"
  subject             = var.github_oidc_subjects[each.key]
}

resource "azurerm_role_assignment" "pipeline_environment" {
  for_each             = azurerm_user_assigned_identity.pipeline
  scope                = azurerm_resource_group.project[each.key].id
  role_definition_name = "Reader"
  principal_id         = each.value.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "pipeline_registry" {
  for_each             = azurerm_user_assigned_identity.pipeline
  scope                = azurerm_container_registry.shared.id
  role_definition_name = "Container Registry Repository Writer"
  condition_version    = "2.0"
  condition            = "@Request[Microsoft.ContainerRegistry/registries/repositories:name] StringEqualsIgnoreCase 'mechmaster/${each.key}-api'"
  principal_id         = each.value.principal_id
  principal_type       = "ServicePrincipal"
}

output "registry_name" {
  value = azurerm_container_registry.shared.name
}

output "github_client_ids" {
  value = { for env, identity in azurerm_user_assigned_identity.pipeline : env => identity.client_id }
}

resource "azurerm_role_assignment" "pipeline_registry_reader" {
  for_each             = azurerm_user_assigned_identity.pipeline
  scope                = azurerm_container_registry.shared.id
  role_definition_name = "Reader"
  principal_id         = each.value.principal_id
  principal_type       = "ServicePrincipal"
}
