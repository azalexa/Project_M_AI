terraform {
  required_version = ">= 1.17.0, < 2.0.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 4.81.0"
    }
  }

  backend "azurerm" {
    use_azuread_auth = true
    container_name   = "tfstate-prod"
    key              = "prod.tfstate"
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy = false
    }
  }

  resource_provider_registrations = "none"
  storage_use_azuread             = true
}
