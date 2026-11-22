module "environment" {
  source = "../../modules/environment"

  environment       = "prod"
  address_space     = "10.40.0.0/24"
  min_replicas      = 1
  static_site_sku   = "Standard"
  postgres_sku      = var.postgres_sku
  database_admin    = var.database_admin
  alert_email       = var.alert_email
}

output "deployment" {
  value = module.environment.deployment
}
