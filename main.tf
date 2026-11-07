locals {
  # OCI accepts `recipients` as a comma-separated string. Trim surrounding
  # whitespace and drop empty entries so a value like "a@example.com, ,"
  # does not reach the API with blank or padded addresses.
  budget_alert_recipients = join(",", compact([
    for recipient in split(",", var.budget_alert_recipients) : trimspace(recipient)
  ]))

  # Deprecated shortcut: a non-null budget_alert_threshold sets the threshold
  # of the `actual` alert, so callers of the single-alert interface keep their
  # threshold without rewriting their config.
  budget_alerts = merge(
    var.budget_alerts,
    var.budget_alert_threshold == null ? {} : {
      actual = {
        type       = "ACTUAL"
        threshold  = var.budget_alert_threshold
        recipients = try(var.budget_alerts["actual"].recipients, null)
      }
    },
  )
}

resource "oci_identity_compartment" "this" {
  compartment_id = var.parent_compartment_id
  name           = var.compartment_name
  description    = var.compartment_description

  # Defaults to false: `terraform destroy` then releases the compartment from
  # state without asking OCI to delete it. A landing-zone compartment is the
  # blast-radius boundary for everything a team owns, so opting in to real
  # deletion is left to the caller.
  enable_delete = var.compartment_enable_delete

  freeform_tags = var.freeform_tags
  defined_tags  = var.defined_tags
}

resource "oci_identity_tag_namespace" "this" {
  compartment_id = var.tenancy_id
  name           = var.tag_namespace_name
  description    = "Governance tag namespace for the ${var.compartment_name} baseline"

  freeform_tags = var.freeform_tags
  defined_tags  = var.defined_tags
}

resource "oci_identity_tag" "this" {
  for_each = toset(var.tag_keys)

  tag_namespace_id = oci_identity_tag_namespace.this.id
  name             = each.value
  description      = "Governance tag ${each.value}"

  # OCI Cost Analysis and TAG-targeted budgets only aggregate on tags that are
  # explicitly marked as cost-tracking; the API default is false. Without this,
  # the CostCenter key this module creates is invisible to every cost report.
  is_cost_tracking = contains(var.cost_tracking_tag_keys, each.value)

  freeform_tags = var.freeform_tags
  defined_tags  = var.defined_tags
}

resource "oci_budget_budget" "this" {
  compartment_id = var.tenancy_id
  display_name   = "${var.compartment_name}-budget"
  description    = "Monthly budget for the ${var.compartment_name} baseline compartment"

  target_type = "COMPARTMENT"
  targets     = [oci_identity_compartment.this.id]

  amount       = var.budget_amount
  reset_period = "MONTHLY"

  freeform_tags = var.freeform_tags
  defined_tags  = var.defined_tags
}

resource "oci_budget_alert_rule" "this" {
  for_each = local.budget_alerts

  budget_id      = oci_budget_budget.this.id
  type           = each.value.type
  threshold      = each.value.threshold
  threshold_type = "PERCENTAGE"
  recipients = each.value.recipients == null ? local.budget_alert_recipients : join(",", compact([
    for recipient in split(",", each.value.recipients) : trimspace(recipient)
  ]))
  message = (each.value.type == "FORECAST"
    ? "The ${var.compartment_name} baseline compartment is forecast to reach ${each.value.threshold}% of its monthly budget."
    : "The ${var.compartment_name} baseline compartment has reached ${each.value.threshold}% of its monthly budget."
  )

  freeform_tags = var.freeform_tags
  defined_tags  = var.defined_tags
}

# Versions up to 1.1.0 managed a single alert rule without for_each. Moving it
# to the `actual` key keeps that rule in place on upgrade instead of
# destroying and recreating it.
moved {
  from = oci_budget_alert_rule.this
  to   = oci_budget_alert_rule.this["actual"]
}

resource "oci_identity_tag_default" "this" {
  for_each = var.tag_defaults

  # Tag defaults are inherited by child compartments, so attaching them to the
  # baseline compartment covers everything created inside the landing zone.
  compartment_id = oci_identity_compartment.this.id
  # try() keeps an unknown key from failing with an index error before the
  # precondition below can report it.
  tag_definition_id = try(oci_identity_tag.this[each.key].id, null)
  value             = each.value.value
  is_required       = each.value.is_required

  lifecycle {
    precondition {
      condition     = contains(var.tag_keys, each.key)
      error_message = "tag_defaults key \"${each.key}\" is not in tag_keys; a tag default can only reference a tag this module creates."
    }
  }
}
