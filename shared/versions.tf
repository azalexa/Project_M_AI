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
    container_name   = "tfstate"
    key              = "shared.tfstate"
  }
}

provider "azurerm" {
  features {}
  resource_provider_registrations = "none"
}
