variable "tenancy_id" {
  description = "OCID of the tenancy the baseline is created under."
  type        = string
}

variable "parent_compartment_id" {
  description = "OCID of the parent compartment (or tenancy) under which the baseline compartment is created."
  type        = string
}

variable "compartment_name" {
  description = "Name of the landing-zone compartment to create."
  type        = string
}

variable "compartment_description" {
  description = "Description of the landing-zone compartment."
  type        = string
  default     = "Landing zone baseline compartment managed by Terraform"
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

variable "budget_alert_threshold" {
  description = "Percentage of the budget at which the alert notifies recipients."
  type        = number
  default     = 80

  validation {
    condition     = var.budget_alert_threshold > 0 && var.budget_alert_threshold <= 100
    error_message = "budget_alert_threshold must be between 1 and 100."
  }
}

variable "budget_alert_recipients" {
  description = <<-EOT
    Comma-separated list of email recipients for the budget alert. Must contain
    at least one address: `recipients` is optional in the OCI API, so a blank
    value produces an alert rule that fires but notifies nobody.
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
