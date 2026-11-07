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
    condition     = alltrue([for r in oci_budget_alert_rule.this : length(trimspace(r.recipients)) > 0])
    error_message = "A budget alert rule was created without recipients; it would notify nobody."
  }
}

run "budget_alert_recipients_are_normalised" {
  variables {
    budget_alert_recipients = " finops@example.com , platform@example.com ,"
  }

  assert {
    condition     = oci_budget_alert_rule.this["actual"].recipients == "finops@example.com,platform@example.com"
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

run "no_tag_defaults_by_default" {
  assert {
    condition     = length(oci_identity_tag_default.this) == 0
    error_message = "Tag defaults must be opt-in so the default plan stays unchanged."
  }
}

run "tag_defaults_attach_to_baseline_compartment" {
  variables {
    tag_defaults = {
      CostCenter = {
        value       = "platform"
        is_required = true
      }
      Environment = {
        value = "production"
      }
    }
  }

  assert {
    condition     = oci_identity_tag_default.this["CostCenter"].compartment_id == oci_identity_compartment.this.id
    error_message = "Tag defaults must be attached to the baseline compartment."
  }

  assert {
    condition     = oci_identity_tag_default.this["CostCenter"].tag_definition_id == oci_identity_tag.this["CostCenter"].id
    error_message = "A tag default must reference the matching tag created by this module."
  }

  assert {
    condition     = oci_identity_tag_default.this["CostCenter"].value == "platform" && oci_identity_tag_default.this["CostCenter"].is_required == true
    error_message = "tag_defaults value and is_required must be passed through."
  }

  assert {
    condition     = oci_identity_tag_default.this["Environment"].is_required == false
    error_message = "is_required must default to false."
  }

  assert {
    condition     = keys(output.tag_default_ids) == ["CostCenter", "Environment"]
    error_message = "tag_default_ids must be keyed by tag name."
  }
}

run "rejects_tag_default_for_unknown_key" {
  command = plan

  variables {
    tag_defaults = {
      Project = {
        value = "alpha"
      }
    }
  }

  expect_failures = [oci_identity_tag_default.this]
}

run "rejects_blank_tag_default_value" {
  command = plan

  variables {
    tag_defaults = {
      Owner = {
        value = "  "
      }
    }
  }

  expect_failures = [var.tag_defaults]
}

run "default_budget_alerts_are_forecast_100_and_actual_80" {
  assert {
    condition     = keys(oci_budget_alert_rule.this) == ["actual", "forecast"]
    error_message = "The default budget_alerts must create one forecast and one actual alert."
  }

  assert {
    condition     = oci_budget_alert_rule.this["forecast"].type == "FORECAST" && oci_budget_alert_rule.this["forecast"].threshold == 100
    error_message = "The default forecast alert must fire at 100% of the forecast."
  }

  assert {
    condition     = oci_budget_alert_rule.this["actual"].type == "ACTUAL" && oci_budget_alert_rule.this["actual"].threshold == 80
    error_message = "The default actual alert must keep the previous 80% threshold."
  }

  assert {
    condition     = oci_budget_alert_rule.this["actual"].message == "The test-lz baseline compartment has reached 80% of its monthly budget."
    error_message = "The actual alert message must match earlier versions so upgrading does not change the existing rule."
  }

  assert {
    condition     = output.budget_alert_rule_id == oci_budget_alert_rule.this["actual"].id
    error_message = "The deprecated budget_alert_rule_id output must point at the actual alert."
  }
}

run "custom_budget_alerts_with_own_recipients" {
  variables {
    budget_alerts = {
      forecast_90 = {
        type       = "FORECAST"
        threshold  = 90
        recipients = " owner@example.com ,"
      }
      actual_100 = {
        type      = "ACTUAL"
        threshold = 100
      }
    }
  }

  assert {
    condition     = keys(oci_budget_alert_rule.this) == ["actual_100", "forecast_90"]
    error_message = "budget_alerts keys must become alert rule instances."
  }

  assert {
    condition     = oci_budget_alert_rule.this["forecast_90"].recipients == "owner@example.com"
    error_message = "Per-alert recipients must be normalised and used instead of budget_alert_recipients."
  }

  assert {
    condition     = oci_budget_alert_rule.this["actual_100"].recipients == "finops@example.com"
    error_message = "An alert without recipients must fall back to budget_alert_recipients."
  }

  assert {
    condition     = output.budget_alert_rule_id == null
    error_message = "budget_alert_rule_id must be null when there is no actual alert."
  }

  assert {
    condition     = keys(output.budget_alert_rule_ids) == ["actual_100", "forecast_90"]
    error_message = "budget_alert_rule_ids must be keyed by budget_alerts key."
  }
}

run "deprecated_threshold_overrides_actual_alert" {
  variables {
    budget_alert_threshold = 90
  }

  assert {
    condition     = oci_budget_alert_rule.this["actual"].threshold == 90
    error_message = "budget_alert_threshold must still set the actual alert threshold."
  }

  assert {
    condition     = oci_budget_alert_rule.this["forecast"].threshold == 100
    error_message = "budget_alert_threshold must not change other alerts."
  }
}

run "rejects_empty_budget_alerts" {
  command = plan

  variables {
    budget_alerts = {}
  }

  expect_failures = [var.budget_alerts]
}

run "rejects_unknown_budget_alert_type" {
  command = plan

  variables {
    budget_alerts = {
      bad = {
        type      = "PREDICTED"
        threshold = 80
      }
    }
  }

  expect_failures = [var.budget_alerts]
}

run "rejects_out_of_range_budget_alert_threshold" {
  command = plan

  variables {
    budget_alerts = {
      bad = {
        type      = "ACTUAL"
        threshold = 0
      }
    }
  }

  expect_failures = [var.budget_alerts]
}

run "rejects_bad_budget_alert_recipients" {
  command = plan

  variables {
    budget_alerts = {
      bad = {
        type       = "ACTUAL"
        threshold  = 80
        recipients = "ops-team"
      }
    }
  }

  expect_failures = [var.budget_alerts]
}
