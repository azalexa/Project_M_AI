terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 4.81.0"
    }
  }
}

variable "environment" {
  type = string
}

variable "address_space" {
  type = string
}

variable "min_replicas" {
  type = number
}

variable "static_site_sku" {
  type = string
}

variable "postgres_sku" {
  type = string
}

variable "database_admin" {
  type = object({
    object_id      = string
    principal_name = string
    principal_type = string
  })
}

variable "alert_email" {
  type     = string
  nullable = true
}
