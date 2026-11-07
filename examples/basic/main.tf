provider "oci" {}

module "baseline" {
  source = "../.."

  tenancy_id            = var.tenancy_id
  parent_compartment_id = var.tenancy_id
  compartment_name      = "example-lz"
  tag_namespace_name    = "example-governance"

  budget_amount           = 250
  budget_alert_recipients = "finops@example.com"

  # Warn when the month is forecast to overspend, and again once actual
  # spend passes 80%.
  budget_alerts = {
    forecast = {
      type      = "FORECAST"
      threshold = 100
    }
    actual = {
      type      = "ACTUAL"
      threshold = 80
    }
  }

  # This example is a throwaway sandbox, so let `terraform destroy` really
  # remove the compartment. Leave the default (false) for anything long-lived.
  compartment_enable_delete = true

  freeform_tags = {
    Environment = "sandbox"
    ManagedBy   = "terraform"
  }
}

variable "tenancy_id" {
  description = "Tenancy OCID the example baseline is created under."
  type        = string
}

output "compartment_id" {
  value = module.baseline.compartment_id
}
