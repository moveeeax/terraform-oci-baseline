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
