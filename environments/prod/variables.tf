variable "postgres_sku" {
  type    = string
  default = "B_Standard_B1ms"
}

variable "database_admin" {
  type = object({
    object_id      = string
    principal_name = string
    principal_type = string
  })
}

variable "alert_email" {
  type = string
}
