# Test-only requirement: `mock_provider` needs Terraform >= 1.7 (OpenTofu >= 1.7).
# The module itself still supports >= 1.5 -- do not raise required_version in
# versions.tf just to run these tests.
mock_provider "oci" {}

variables {
  tenancy_id              = "ocid1.tenancy.oc1..aaaaaaaaexampletenancy"
  parent_compartment_id   = "ocid1.tenancy.oc1..aaaaaaaaexampletenancy"
  compartment_name        = "test-lz"
  tag_namespace_name      = "test-governance"
  budget_alert_recipients = "finops@example.com"
}

run "compartment_is_not_deletable_by_default" {
  assert {
    condition     = oci_identity_compartment.this.enable_delete == false
    error_message = "The landing-zone compartment must not be really deleted on terraform destroy unless the caller opts in."
  }
}

run "compartment_delete_can_be_opted_into" {
  variables {
    compartment_enable_delete = true
  }

  assert {
    condition     = oci_identity_compartment.this.enable_delete == true
    error_message = "compartment_enable_delete must be honoured when set to true."
  }
}

run "budget_alert_has_recipients" {
  assert {
    condition     = length(trimspace(oci_budget_alert_rule.this.recipients)) > 0
    error_message = "The budget alert rule was created without recipients; it would notify nobody."
  }
}

run "budget_alert_recipients_are_normalised" {
  variables {
    budget_alert_recipients = " finops@example.com , platform@example.com ,"
  }

  assert {
    condition     = oci_budget_alert_rule.this.recipients == "finops@example.com,platform@example.com"
    error_message = "Recipient list must be trimmed and stripped of empty entries before it reaches the OCI API."
  }
}

run "budget_targets_the_created_compartment" {
  assert {
    condition     = oci_budget_budget.this.target_type == "COMPARTMENT"
    error_message = "The budget must target a compartment."
  }

  assert {
    condition     = oci_budget_budget.this.targets == tolist([oci_identity_compartment.this.id])
    error_message = "The budget must target the compartment this module creates."
  }

  assert {
    condition     = oci_budget_budget.this.reset_period == "MONTHLY"
    error_message = "The baseline budget is documented as monthly."
  }
}

run "cost_center_tag_is_cost_tracking_by_default" {
  assert {
    condition     = oci_identity_tag.this["CostCenter"].is_cost_tracking == true
    error_message = "The CostCenter governance tag must be cost-tracking, otherwise OCI Cost Analysis ignores it."
  }

  assert {
    condition     = oci_identity_tag.this["Environment"].is_cost_tracking == false
    error_message = "Only keys listed in cost_tracking_tag_keys should consume a tenancy cost-tracking tag slot."
  }
}

run "unknown_cost_tracking_keys_are_ignored" {
  variables {
    tag_keys               = ["Environment"]
    cost_tracking_tag_keys = ["CostCenter"]
  }

  assert {
    condition     = oci_identity_tag.this["Environment"].is_cost_tracking == false
    error_message = "A cost-tracking key that is not in tag_keys must not affect the tags that are created."
  }
}

run "rejects_blank_recipients" {
  command = plan

  variables {
    budget_alert_recipients = "  ,  "
  }

  expect_failures = [var.budget_alert_recipients]
}

run "rejects_empty_recipients" {
  command = plan

  variables {
    budget_alert_recipients = ""
  }

  expect_failures = [var.budget_alert_recipients]
}

run "rejects_non_email_recipients" {
  command = plan

  variables {
    budget_alert_recipients = "finops@example.com,ops-team"
  }

  expect_failures = [var.budget_alert_recipients]
}

run "rejects_non_positive_budget" {
  command = plan

  variables {
    budget_amount = 0
  }

  expect_failures = [var.budget_amount]
}

run "rejects_out_of_range_threshold" {
  command = plan

  variables {
    budget_alert_threshold = 101
  }

  expect_failures = [var.budget_alert_threshold]
}

run "rejects_too_many_cost_tracking_keys" {
  command = plan

  variables {
    cost_tracking_tag_keys = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k"]
  }

  expect_failures = [var.cost_tracking_tag_keys]
}
