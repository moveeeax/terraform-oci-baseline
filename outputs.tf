output "compartment_id" {
  description = "OCID of the landing-zone compartment."
  value       = oci_identity_compartment.this.id
}

output "tag_namespace_id" {
  description = "OCID of the governance tag namespace."
  value       = oci_identity_tag_namespace.this.id
}

output "tag_ids" {
  description = "Map of tag key name to tag OCID."
  value       = { for k, t in oci_identity_tag.this : k => t.id }
}

output "tag_default_ids" {
  description = "Map of tag key name to tag default OCID, for the keys in tag_defaults."
  value       = { for k, d in oci_identity_tag_default.this : k => d.id }
}

output "budget_id" {
  description = "OCID of the compartment budget."
  value       = oci_budget_budget.this.id
}

output "budget_alert_rule_ids" {
  description = "Map of budget_alerts key to budget alert rule OCID."
  value       = { for k, r in oci_budget_alert_rule.this : k => r.id }
}

output "budget_alert_rule_id" {
  description = "Deprecated: use budget_alert_rule_ids. OCID of the `actual` budget alert rule, or null if there is none."
  value       = try(oci_budget_alert_rule.this["actual"].id, null)
}

output "compartment_ids" {
  description = "Map of compartments key to compartment OCID."
  value = merge(
    { for k, c in oci_identity_compartment.level_1 : k => c.id },
    { for k, c in oci_identity_compartment.level_2 : k => c.id },
    { for k, c in oci_identity_compartment.level_3 : k => c.id },
    { for k, c in oci_identity_compartment.level_4 : k => c.id },
    { for k, c in oci_identity_compartment.level_5 : k => c.id },
  )
}

output "compartment_path" {
  description = "Name path of the baseline compartment from the tenancy, as used in quota and IAM policy statements; null when the parent is not the tenancy and parent_compartment_path is not set."
  value       = local.compartment_path
}

output "compartment_paths" {
  description = "Map of compartments key to name path from the tenancy; values are null when compartment_path is null."
  value       = local.compartment_paths
}

output "quota_id" {
  description = "OCID of the compartment quota policy, or null when quota_statements is empty."
  value       = try(oci_limits_quota.this[0].id, null)
}
