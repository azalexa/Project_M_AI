variable "alert_email" {
  type        = string
  description = "Recipient of Azure budget alerts."
}

variable "budget_start" {
  type        = string
  description = "First day of the current UTC month in RFC3339 format."
}

variable "monthly_budgets" {
  type        = object({ dev = number, prod = number, shared = number })
  description = "Monthly Azure Cost Management thresholds in the billing currency."
}

variable "github_oidc_subjects" {
  type        = map(string)
  default     = {}
  description = "Verified GitHub OIDC subject for each environment. An empty map disables federation."
  validation {
    condition = alltrue([
      for env, subject in var.github_oidc_subjects :
      contains(["dev", "prod"], env) && can(regex("^repo:azalexa(@[0-9]+)?/Project_M_AI(@[0-9]+)?:environment:${env}$", subject))
    ])
    error_message = "Provide exact, verified GitHub environment subjects for dev or prod."
  }
}

variable "github_state_read_enabled" {
  type        = bool
  default     = false
  description = "Allow GitHub speculative plans to read every state in the shared container."
}

variable "state_account_name" {
  type        = string
  description = "Name of the bootstrapped Terraform Storage account."
}
