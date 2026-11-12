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

  lifecycle {
    precondition {
      condition     = length(local.compartments_unresolved) == 0
      error_message = "compartments entries ${jsonencode(sort(tolist(local.compartments_unresolved)))} are nested more than five levels below the baseline compartment or form a parent_key cycle."
    }

    precondition {
      condition     = local.baseline_depth == null ? true : local.baseline_depth + local.compartments_depth <= 6
      error_message = "The baseline compartment sits ${coalesce(local.baseline_depth, 0)} level(s) below the tenancy and compartments adds ${local.compartments_depth} more; OCI allows at most 6 nested levels."
    }
  }
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

# Compartment tree under the baseline compartment. Terraform has no recursion,
# so each nesting level is its own resource and an entry lands on the level
# its parent_key chain resolves to. OCI allows six nested levels below the
# tenancy; the baseline compartment takes at least one, which leaves five.
locals {
  compartments = {
    for k, c in var.compartments : k => merge(c, {
      name          = coalesce(c.name, k)
      freeform_tags = merge(var.freeform_tags, coalesce(c.freeform_tags, {}))
      defined_tags  = merge(var.defined_tags, coalesce(c.defined_tags, {}))
    })
  }

  compartments_level_1 = { for k, c in local.compartments : k => c if c.parent_key == null }
  compartments_level_2 = { for k, c in local.compartments : k => c if c.parent_key == null ? false : contains(keys(local.compartments_level_1), c.parent_key) }
  compartments_level_3 = { for k, c in local.compartments : k => c if c.parent_key == null ? false : contains(keys(local.compartments_level_2), c.parent_key) }
  compartments_level_4 = { for k, c in local.compartments : k => c if c.parent_key == null ? false : contains(keys(local.compartments_level_3), c.parent_key) }
  compartments_level_5 = { for k, c in local.compartments : k => c if c.parent_key == null ? false : contains(keys(local.compartments_level_4), c.parent_key) }

  # Entries left over after five levels are either nested too deep or part of
  # a parent_key cycle; the precondition on the baseline compartment reports
  # them by key.
  compartments_unresolved = setsubtract(keys(local.compartments), concat(
    keys(local.compartments_level_1),
    keys(local.compartments_level_2),
    keys(local.compartments_level_3),
    keys(local.compartments_level_4),
    keys(local.compartments_level_5),
  ))

  compartments_depth = (
    length(local.compartments_level_5) > 0 ? 5 :
    length(local.compartments_level_4) > 0 ? 4 :
    length(local.compartments_level_3) > 0 ? 3 :
    length(local.compartments_level_2) > 0 ? 2 :
    length(local.compartments_level_1) > 0 ? 1 : 0
  )

  # Depth of the baseline compartment below the tenancy, when it can be known
  # without an API call.
  baseline_depth = (
    var.parent_compartment_id == var.tenancy_id ? 1 :
    var.parent_compartment_path == null ? null : length(split(":", var.parent_compartment_path)) + 1
  )

  # Quota statements address compartments by their name path from the
  # tenancy, e.g. "parent:child". Null when the parent path is not known.
  compartment_path = (
    var.parent_compartment_id == var.tenancy_id ? var.compartment_name :
    var.parent_compartment_path == null ? null : "${var.parent_compartment_path}:${var.compartment_name}"
  )

  compartment_paths_level_1 = { for k, c in local.compartments_level_1 : k => local.compartment_path == null ? null : "${local.compartment_path}:${c.name}" }
  compartment_paths_level_2 = { for k, c in local.compartments_level_2 : k => local.compartment_paths_level_1[c.parent_key] == null ? null : "${local.compartment_paths_level_1[c.parent_key]}:${c.name}" }
  compartment_paths_level_3 = { for k, c in local.compartments_level_3 : k => local.compartment_paths_level_2[c.parent_key] == null ? null : "${local.compartment_paths_level_2[c.parent_key]}:${c.name}" }
  compartment_paths_level_4 = { for k, c in local.compartments_level_4 : k => local.compartment_paths_level_3[c.parent_key] == null ? null : "${local.compartment_paths_level_3[c.parent_key]}:${c.name}" }
  compartment_paths_level_5 = { for k, c in local.compartments_level_5 : k => local.compartment_paths_level_4[c.parent_key] == null ? null : "${local.compartment_paths_level_4[c.parent_key]}:${c.name}" }

  compartment_paths = merge(
    local.compartment_paths_level_1,
    local.compartment_paths_level_2,
    local.compartment_paths_level_3,
    local.compartment_paths_level_4,
    local.compartment_paths_level_5,
  )
}

resource "oci_identity_compartment" "level_1" {
  for_each = local.compartments_level_1

  compartment_id = oci_identity_compartment.this.id
  name           = each.value.name
  description    = each.value.description
  enable_delete  = each.value.enable_delete

  freeform_tags = each.value.freeform_tags
  defined_tags  = each.value.defined_tags
}

resource "oci_identity_compartment" "level_2" {
  for_each = local.compartments_level_2

  compartment_id = oci_identity_compartment.level_1[each.value.parent_key].id
  name           = each.value.name
  description    = each.value.description
  enable_delete  = each.value.enable_delete

  freeform_tags = each.value.freeform_tags
  defined_tags  = each.value.defined_tags
}

resource "oci_identity_compartment" "level_3" {
  for_each = local.compartments_level_3

  compartment_id = oci_identity_compartment.level_2[each.value.parent_key].id
  name           = each.value.name
  description    = each.value.description
  enable_delete  = each.value.enable_delete

  freeform_tags = each.value.freeform_tags
  defined_tags  = each.value.defined_tags
}

resource "oci_identity_compartment" "level_4" {
  for_each = local.compartments_level_4

  compartment_id = oci_identity_compartment.level_3[each.value.parent_key].id
  name           = each.value.name
  description    = each.value.description
  enable_delete  = each.value.enable_delete

  freeform_tags = each.value.freeform_tags
  defined_tags  = each.value.defined_tags
}

resource "oci_identity_compartment" "level_5" {
  for_each = local.compartments_level_5

  compartment_id = oci_identity_compartment.level_4[each.value.parent_key].id
  name           = each.value.name
  description    = each.value.description
  enable_delete  = each.value.enable_delete

  freeform_tags = each.value.freeform_tags
  defined_tags  = each.value.defined_tags
}

# Compartment quotas. Quota policies always live in the root compartment and
# name their target by path, so {compartment} and {compartments.<key>}
# placeholders are replaced with the name paths computed above.
locals {
  quota_statements = [
    for s in var.quota_statements : join("", [
      for part in regexall("\\{compartments?(?:\\.[^}]+)?\\}|[^{]+|\\{", s) : (
        part == "{compartment}" ? coalesce(local.compartment_path, part) :
        startswith(part, "{compartments.") ? coalesce(lookup(local.compartment_paths, trimsuffix(trimprefix(part, "{compartments."), "}"), null), part) :
        part
      )
    ])
  ]

  # Placeholders left in a statement after substitution: an unknown key, or
  # a path that cannot be built without parent_compartment_path.
  quota_unresolved_placeholders = distinct(flatten([
    for s in local.quota_statements : regexall("\\{compartments?(?:\\.[^}]+)?\\}", s)
  ]))
}

resource "oci_limits_quota" "this" {
  count = length(var.quota_statements) > 0 ? 1 : 0

  # The Limits API only accepts the root compartment for quota policies.
  compartment_id = var.tenancy_id
  name           = coalesce(var.quota_name, "${var.compartment_name}-quota")
  description    = "Compartment quotas for the ${var.compartment_name} baseline"
  statements     = local.quota_statements

  freeform_tags = var.freeform_tags
  defined_tags  = var.defined_tags

  lifecycle {
    precondition {
      condition     = length(local.quota_unresolved_placeholders) == 0
      error_message = "quota_statements placeholders could not be resolved: ${join(", ", local.quota_unresolved_placeholders)}. {compartments.<key>} needs a key from compartments, and paths below a non-tenancy parent need parent_compartment_path."
    }
  }
}
