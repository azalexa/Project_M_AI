module "environment" {
  source = "../../modules/environment"

  environment     = "dev"
  address_space   = "10.30.0.0/24"
  min_replicas    = 0
  static_site_sku = "Free"
  postgres_sku    = var.postgres_sku
  database_admin  = var.database_admin
  alert_email     = null
}

output "deployment" {
  value = module.environment.deployment
}
