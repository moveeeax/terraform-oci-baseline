variable "tenancy_id" {
  description = "OCID of the tenancy the baseline is created under."
  type        = string
}

variable "parent_compartment_id" {
  description = "OCID of the parent compartment (or tenancy) under which the baseline compartment is created."
  type        = string
}

variable "parent_compartment_path" {
  description = <<-EOT
    Name path of `parent_compartment_id` from the tenancy, colon-separated,
    e.g. "shared:landing-zones". Only used to address compartments in
    `quota_statements` and to check the OCI nesting limit; leave null when
    the parent is the tenancy.
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.parent_compartment_path == null ? true : can(regex("^[A-Za-z0-9._-]{1,100}(:[A-Za-z0-9._-]{1,100})*$", var.parent_compartment_path))
    error_message = "parent_compartment_path must be compartment names separated by \":\", e.g. \"shared:landing-zones\"."
  }
}

variable "compartment_name" {
  description = "Name of the landing-zone compartment to create. Letters, digits, periods, hyphens and underscores; 1-100 characters."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]{1,100}$", var.compartment_name))
    error_message = "compartment_name must be 1-100 letters, digits, periods, hyphens or underscores; OCI rejects other characters at apply time."
  }
}

variable "compartment_description" {
  description = "Description of the landing-zone compartment."
  type        = string
  default     = "Landing zone baseline compartment managed by Terraform"

  validation {
    condition     = length(var.compartment_description) >= 1 && length(var.compartment_description) <= 400
    error_message = "compartment_description must be between 1 and 400 characters."
  }
}

variable "tag_namespace_name" {
  description = "Name of the defined-tag namespace created for governance tagging."
  type        = string
}

variable "compartment_enable_delete" {
  description = <<-EOT
    Whether `terraform destroy` should actually delete the compartment in OCI.
    Defaults to false, matching the provider default: the compartment is
    released from Terraform state but left in place. Set to true only for
    throwaway environments -- a landing-zone compartment is the blast-radius
    boundary for every resource a team owns.
  EOT
  type        = bool
  default     = false
}

variable "compartments" {
  description = <<-EOT
    Compartment tree to create under the baseline compartment, keyed by a
    name of your choice. An entry without `parent_key` is a direct child of
    the baseline compartment; `parent_key` names another entry to nest under.
    `name` defaults to the key, so two entries can share a name under
    different parents (e.g. a "network" compartment per environment).
    `freeform_tags` and `defined_tags` are merged over the module-level tags.
    `enable_delete` defaults to false, as for the baseline compartment.
    Up to five levels below the baseline compartment.
  EOT
  type = map(object({
    description   = string
    name          = optional(string)
    parent_key    = optional(string)
    enable_delete = optional(bool, false)
    freeform_tags = optional(map(string))
    defined_tags  = optional(map(string))
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, c in var.compartments : c.parent_key == null ? true : (c.parent_key != k && contains(keys(var.compartments), c.parent_key))
    ])
    error_message = "Every compartments parent_key must be the key of another entry in compartments."
  }

  validation {
    condition     = alltrue([for k, c in var.compartments : can(regex("^[A-Za-z0-9._-]{1,100}$", coalesce(c.name, k)))])
    error_message = "Every compartments name (the key when name is omitted) must be 1-100 letters, digits, periods, hyphens or underscores."
  }

  validation {
    condition     = alltrue([for c in values(var.compartments) : length(c.description) >= 1 && length(c.description) <= 400])
    error_message = "Every compartments description must be between 1 and 400 characters."
  }

  validation {
    # OCI rejects two compartments with the same name under one parent.
    condition = length(distinct([
      for k, c in var.compartments : "${coalesce(c.parent_key, "\u0000")}/${lower(coalesce(c.name, k))}"
    ])) == length(var.compartments)
    error_message = "Two compartments entries with the same parent_key have the same name; OCI requires names to be unique within a parent."
  }
}

variable "tag_keys" {
  description = "List of defined-tag keys to create in the namespace."
  type        = list(string)
  default     = ["Environment", "Owner", "CostCenter"]
}

variable "cost_tracking_tag_keys" {
  description = <<-EOT
    Tag keys from `tag_keys` to mark as cost-tracking. OCI Cost Analysis and
    TAG-targeted budgets only aggregate spend on tags flagged this way, so a
    cost-allocation key that is not listed here cannot be used for chargeback.
    Keys not present in `tag_keys` are ignored. OCI allows at most 10
    cost-tracking tags per tenancy.
  EOT
  type        = list(string)
  default     = ["CostCenter"]

  validation {
    condition     = length(var.cost_tracking_tag_keys) <= 10
    error_message = "cost_tracking_tag_keys may contain at most 10 keys; OCI limits a tenancy to 10 cost-tracking tags."
  }
}

variable "tag_defaults" {
  description = <<-EOT
    Tag defaults to attach to the baseline compartment, keyed by a tag name
    from `tag_keys`. OCI applies the value to every resource created in the
    compartment and its children. With `is_required = true` OCI blocks
    resource creation in the compartment unless a value for the tag is set,
    which is what keeps resources out of the untagged bucket in cost reports.
    Keys must also be listed in `tag_keys`.
  EOT
  type = map(object({
    value       = string
    is_required = optional(bool, false)
  }))
  default = {}

  validation {
    condition     = alltrue([for d in values(var.tag_defaults) : length(trimspace(d.value)) > 0])
    error_message = "Every tag_defaults entry must have a non-empty value."
  }
}

variable "budget_amount" {
  description = "Monthly budget amount, in the tenancy currency, tracking the baseline compartment."
  type        = number
  default     = 100

  validation {
    condition     = var.budget_amount > 0
    error_message = "budget_amount must be greater than zero."
  }
}

variable "budget_alerts" {
  description = <<-EOT
    Budget alert rules, keyed by a name of your choice. `type` is "ACTUAL"
    (spend so far) or "FORECAST" (spend OCI projects for the month);
    `threshold` is a percentage of `budget_amount`. `recipients` is a
    comma-separated email list and falls back to `budget_alert_recipients`
    when omitted. The default pairs a forecast alert at 100% as the early
    warning with an actual-spend alert at 80%. The `actual` key is the rule
    earlier versions created, so keep it to avoid replacing that rule.
  EOT
  type = map(object({
    type       = string
    threshold  = number
    recipients = optional(string)
  }))
  default = {
    forecast = {
      type      = "FORECAST"
      threshold = 100
    }
    actual = {
      type      = "ACTUAL"
      threshold = 80
    }
  }

  validation {
    condition     = length(var.budget_alerts) > 0
    error_message = "budget_alerts must contain at least one alert; a budget without alerts notifies nobody."
  }

  validation {
    condition     = alltrue([for a in values(var.budget_alerts) : contains(["ACTUAL", "FORECAST"], a.type)])
    error_message = "Every budget_alerts entry must have type \"ACTUAL\" or \"FORECAST\"."
  }

  validation {
    condition     = alltrue([for a in values(var.budget_alerts) : a.threshold > 0 && a.threshold <= 100])
    error_message = "Every budget_alerts threshold must be between 1 and 100."
  }

  validation {
    condition = alltrue([
      for a in values(var.budget_alerts) : a.recipients == null ? true : (
        length(compact([for r in split(",", a.recipients) : trimspace(r)])) > 0 &&
        alltrue([
          for r in compact([for r in split(",", a.recipients) : trimspace(r)]) :
          can(regex("^[^@,[:space:]]+@[^@,[:space:]]+\\.[^@,[:space:]]+$", r))
        ])
      )
    ])
    error_message = "budget_alerts recipients, when set, must be a non-empty comma-separated list of email addresses; omit it to use budget_alert_recipients."
  }
}

variable "budget_alert_threshold" {
  description = <<-EOT
    Deprecated: use `budget_alerts`. When set, overrides the threshold of the
    `actual` entry in `budget_alerts` (adding it if missing). Defaults to null,
    which leaves `budget_alerts` as given.
  EOT
  type        = number
  default     = null

  validation {
    condition     = var.budget_alert_threshold == null ? true : (var.budget_alert_threshold > 0 && var.budget_alert_threshold <= 100)
    error_message = "budget_alert_threshold must be between 1 and 100."
  }
}

variable "budget_alert_recipients" {
  description = <<-EOT
    Comma-separated list of email recipients for budget alerts that do not set
    their own `recipients` in `budget_alerts`. Must contain at least one
    address: `recipients` is optional in the OCI API, so a blank value
    produces an alert rule that fires but notifies nobody.
  EOT
  type        = string

  validation {
    condition = length(compact([
      for recipient in split(",", var.budget_alert_recipients) : trimspace(recipient)
    ])) > 0
    error_message = "budget_alert_recipients must contain at least one email address; a blank value creates a budget alert rule that notifies nobody."
  }

  validation {
    condition = alltrue([
      for recipient in compact([
        for r in split(",", var.budget_alert_recipients) : trimspace(r)
      ]) : can(regex("^[^@,[:space:]]+@[^@,[:space:]]+\\.[^@,[:space:]]+$", recipient))
    ])
    error_message = "Every entry in budget_alert_recipients must be an email address, e.g. \"finops@example.com,platform@example.com\"."
  }
}

variable "quota_statements" {
  description = <<-EOT
    Compartment quota statements, e.g.
    "set compute quota standard-e4-core-count to 16 in compartment {compartment}".
    `{compartment}` is replaced with the name path of the baseline compartment
    and `{compartments.<key>}` with the path of an entry in `compartments`.
    Statements are kept in order in one `oci_limits_quota` policy in the
    tenancy. Empty by default: no quota policy is created.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for s in var.quota_statements : length(trimspace(s)) > 0])
    error_message = "quota_statements must not contain blank statements."
  }
}

variable "quota_name" {
  description = "Name of the quota policy. Must be unique in the tenancy and cannot be changed after creation. Defaults to \"<compartment_name>-quota\"."
  type        = string
  default     = null
}

variable "freeform_tags" {
  description = "Free-form tags applied to the baseline resources."
  type        = map(string)
  default     = {}
}

variable "defined_tags" {
  description = "Defined tags applied to the baseline resources, keyed as \"namespace.key\"."
  type        = map(string)
  default     = {}
}
