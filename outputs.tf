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

output "budget_alert_rule_id" {
  description = "OCID of the budget alert rule."
  value       = oci_budget_alert_rule.this.id
}
