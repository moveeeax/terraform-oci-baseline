# Compartment tree and quota tests. Same mocked provider as defaults.tftest.hcl.
mock_provider "oci" {}

variables {
  tenancy_id              = "ocid1.tenancy.oc1..aaaaaaaaexampletenancy"
  parent_compartment_id   = "ocid1.tenancy.oc1..aaaaaaaaexampletenancy"
  compartment_name        = "test-lz"
  tag_namespace_name      = "test-governance"
  budget_alert_recipients = "finops@example.com"
}

run "no_tree_and_no_quota_by_default" {
  assert {
    condition     = length(output.compartment_ids) == 0
    error_message = "The compartment tree must be opt-in so the default plan stays unchanged."
  }

  assert {
    condition     = length(oci_limits_quota.this) == 0 && output.quota_id == null
    error_message = "No quota policy may be created without quota_statements."
  }

  assert {
    condition     = output.compartment_path == "test-lz"
    error_message = "A baseline compartment directly under the tenancy has its own name as path."
  }
}

run "tree_is_wired_by_parent_key" {
  variables {
    freeform_tags = {
      ManagedBy = "terraform"
    }

    compartments = {
      prod = {
        description = "Production"
      }
      prod-network = {
        name          = "network"
        description   = "Production network"
        parent_key    = "prod"
        enable_delete = true
        freeform_tags = {
          Layer = "network"
        }
      }
      dev = {
        description = "Development"
      }
      dev-network = {
        name        = "network"
        description = "Development network"
        parent_key  = "dev"
      }
      prod-network-edge = {
        name        = "edge"
        description = "Production edge"
        parent_key  = "prod-network"
      }
    }
  }

  assert {
    condition     = keys(oci_identity_compartment.level_1) == ["dev", "prod"]
    error_message = "Entries without parent_key must be the first level of the tree."
  }

  assert {
    condition     = oci_identity_compartment.level_1["prod"].compartment_id == oci_identity_compartment.this.id
    error_message = "First-level compartments must be created under the baseline compartment."
  }

  assert {
    condition     = oci_identity_compartment.level_2["prod-network"].compartment_id == oci_identity_compartment.level_1["prod"].id
    error_message = "A second-level compartment must be created under its parent_key."
  }

  assert {
    condition     = oci_identity_compartment.level_3["prod-network-edge"].compartment_id == oci_identity_compartment.level_2["prod-network"].id
    error_message = "A third-level compartment must be created under its parent_key."
  }

  assert {
    condition     = oci_identity_compartment.level_2["prod-network"].name == "network" && oci_identity_compartment.level_1["prod"].name == "prod"
    error_message = "name must default to the key and be passed through when set."
  }

  assert {
    condition     = oci_identity_compartment.level_2["prod-network"].enable_delete == true && oci_identity_compartment.level_2["dev-network"].enable_delete == false
    error_message = "enable_delete must default to false and be passed through when set."
  }

  assert {
    condition     = oci_identity_compartment.level_2["prod-network"].freeform_tags == tomap({ ManagedBy = "terraform", Layer = "network" })
    error_message = "Per-entry freeform_tags must be merged over the module-level tags."
  }

  assert {
    condition     = oci_identity_compartment.level_1["dev"].freeform_tags == tomap({ ManagedBy = "terraform" })
    error_message = "Entries without their own tags must get the module-level tags."
  }

  assert {
    condition     = keys(output.compartment_ids) == ["dev", "dev-network", "prod", "prod-network", "prod-network-edge"]
    error_message = "compartment_ids must contain every compartments key."
  }

  assert {
    condition     = output.compartment_ids["prod-network-edge"] == oci_identity_compartment.level_3["prod-network-edge"].id
    error_message = "compartment_ids must map keys to compartment OCIDs."
  }

  assert {
    condition     = output.compartment_paths["prod-network-edge"] == "test-lz:prod:network:edge"
    error_message = "compartment_paths must be the colon-separated name path from the tenancy."
  }
}

run "five_levels_below_baseline_are_allowed" {
  variables {
    compartments = {
      l1 = { description = "Level 1" }
      l2 = { description = "Level 2", parent_key = "l1" }
      l3 = { description = "Level 3", parent_key = "l2" }
      l4 = { description = "Level 4", parent_key = "l3" }
      l5 = { description = "Level 5", parent_key = "l4" }
    }
  }

  assert {
    condition     = oci_identity_compartment.level_5["l5"].compartment_id == oci_identity_compartment.level_4["l4"].id
    error_message = "The fifth level must be created under the fourth."
  }
}

run "rejects_sixth_level_below_baseline" {
  command = plan

  variables {
    compartments = {
      l1 = { description = "Level 1" }
      l2 = { description = "Level 2", parent_key = "l1" }
      l3 = { description = "Level 3", parent_key = "l2" }
      l4 = { description = "Level 4", parent_key = "l3" }
      l5 = { description = "Level 5", parent_key = "l4" }
      l6 = { description = "Level 6", parent_key = "l5" }
    }
  }

  expect_failures = [oci_identity_compartment.this]
}

run "rejects_parent_key_cycle" {
  command = plan

  variables {
    compartments = {
      a = { description = "A", parent_key = "b" }
      b = { description = "B", parent_key = "a" }
    }
  }

  expect_failures = [oci_identity_compartment.this]
}

run "rejects_tree_deeper_than_oci_limit_under_known_parent_path" {
  command = plan

  variables {
    parent_compartment_id   = "ocid1.compartment.oc1..aaaaaaaaexampleparent"
    parent_compartment_path = "shared:landing-zones"
    compartments = {
      l1 = { description = "Level 1" }
      l2 = { description = "Level 2", parent_key = "l1" }
      l3 = { description = "Level 3", parent_key = "l2" }
      l4 = { description = "Level 4", parent_key = "l3" }
    }
  }

  expect_failures = [oci_identity_compartment.this]
}

run "rejects_unknown_parent_key" {
  command = plan

  variables {
    compartments = {
      app = { description = "App", parent_key = "prod" }
    }
  }

  expect_failures = [var.compartments]
}

run "rejects_duplicate_sibling_names" {
  command = plan

  variables {
    compartments = {
      network   = { description = "Network" }
      network-2 = { name = "Network", description = "Another network" }
    }
  }

  expect_failures = [var.compartments]
}

run "rejects_invalid_compartment_name" {
  command = plan

  variables {
    compartments = {
      app = { name = "my app", description = "App" }
    }
  }

  expect_failures = [var.compartments]
}

run "rejects_empty_compartment_description" {
  command = plan

  variables {
    compartments = {
      app = { description = "" }
    }
  }

  expect_failures = [var.compartments]
}

run "rejects_invalid_baseline_compartment_name" {
  command = plan

  variables {
    compartment_name = "team alpha"
  }

  expect_failures = [var.compartment_name]
}

run "quota_statements_substitute_compartment_paths" {
  variables {
    compartments = {
      prod = { description = "Production" }
    }

    quota_statements = [
      "set compute quota standard-e4-core-count to 16 in compartment {compartment}",
      "zero database quota /*exadata*/ in compartment {compartments.prod} where request.region = 'us-phoenix-1'",
    ]
  }

  assert {
    condition = oci_limits_quota.this[0].statements == tolist([
      "set compute quota standard-e4-core-count to 16 in compartment test-lz",
      "zero database quota /*exadata*/ in compartment test-lz:prod where request.region = 'us-phoenix-1'",
    ])
    error_message = "{compartment} and {compartments.<key>} must be replaced with name paths from the tenancy."
  }

  assert {
    condition     = oci_limits_quota.this[0].compartment_id == "ocid1.tenancy.oc1..aaaaaaaaexampletenancy"
    error_message = "Quota policies must be created in the tenancy."
  }

  assert {
    condition     = oci_limits_quota.this[0].name == "test-lz-quota"
    error_message = "quota_name must default to <compartment_name>-quota."
  }

  assert {
    condition     = output.quota_id == oci_limits_quota.this[0].id
    error_message = "quota_id must point at the quota policy."
  }
}

run "quota_path_uses_parent_compartment_path" {
  variables {
    parent_compartment_id   = "ocid1.compartment.oc1..aaaaaaaaexampleparent"
    parent_compartment_path = "shared:landing-zones"
    quota_name              = "alpha-quota"
    quota_statements = [
      "set compute quota standard-e4-core-count to 16 in compartment {compartment}",
    ]
  }

  assert {
    condition     = oci_limits_quota.this[0].statements[0] == "set compute quota standard-e4-core-count to 16 in compartment shared:landing-zones:test-lz"
    error_message = "The baseline path must start with parent_compartment_path."
  }

  assert {
    condition     = oci_limits_quota.this[0].name == "alpha-quota"
    error_message = "quota_name must be passed through when set."
  }
}

run "statements_without_placeholders_are_kept_verbatim" {
  variables {
    parent_compartment_id = "ocid1.compartment.oc1..aaaaaaaaexampleparent"
    quota_statements = [
      "zero database quota /*exadata*/ in tenancy where request.region = 'us-ashburn-1'",
    ]
  }

  assert {
    condition     = oci_limits_quota.this[0].statements == tolist(["zero database quota /*exadata*/ in tenancy where request.region = 'us-ashburn-1'"])
    error_message = "Statements without placeholders must reach the API unchanged."
  }
}

run "rejects_compartment_placeholder_without_parent_path" {
  command = plan

  variables {
    parent_compartment_id = "ocid1.compartment.oc1..aaaaaaaaexampleparent"
    quota_statements = [
      "set compute quota standard-e4-core-count to 16 in compartment {compartment}",
    ]
  }

  expect_failures = [oci_limits_quota.this]
}

run "rejects_unknown_compartments_placeholder" {
  command = plan

  variables {
    quota_statements = [
      "zero database quota /*exadata*/ in compartment {compartments.missing}",
    ]
  }

  expect_failures = [oci_limits_quota.this]
}

run "rejects_blank_quota_statement" {
  command = plan

  variables {
    quota_statements = [" "]
  }

  expect_failures = [var.quota_statements]
}
