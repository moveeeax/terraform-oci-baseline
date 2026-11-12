provider "oci" {}

# A landing zone with prod and dev environments, each split into network and
# app compartments, plus quotas that cap compute in the whole landing zone
# and keep Exadata databases out of dev.
module "baseline" {
  source = "../.."

  tenancy_id            = var.tenancy_id
  parent_compartment_id = var.tenancy_id
  compartment_name      = "example-lz"
  tag_namespace_name    = "example-lz-governance"

  budget_alert_recipients = "finops@example.com"

  compartments = {
    prod = {
      description = "Production workloads"
    }
    prod-network = {
      name        = "network"
      description = "Production networking"
      parent_key  = "prod"
    }
    prod-app = {
      name        = "app"
      description = "Production applications"
      parent_key  = "prod"
    }
    dev = {
      description = "Development workloads"
      freeform_tags = {
        Environment = "dev"
      }
    }
    dev-network = {
      name        = "network"
      description = "Development networking"
      parent_key  = "dev"
    }
    dev-app = {
      name        = "app"
      description = "Development applications"
      parent_key  = "dev"
    }
  }

  quota_statements = [
    "set compute quota standard-e4-core-count to 32 in compartment {compartment}",
    "zero database quota /*exadata*/ in compartment {compartments.dev}",
  ]

  freeform_tags = {
    ManagedBy = "terraform"
  }
}

variable "tenancy_id" {
  description = "Tenancy OCID the example baseline is created under."
  type        = string
}

output "compartment_ids" {
  value = module.baseline.compartment_ids
}
