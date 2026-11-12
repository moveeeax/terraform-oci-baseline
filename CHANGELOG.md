# Changelog

All notable changes to this module are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the module uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- `compartments` input: a compartment tree under the baseline compartment
  from one map, nested by `parent_key` up to five levels, with per-entry
  `name`, `enable_delete` (default `false`) and tags merged over the
  module-level tags. Empty by default. Replaces the archived
  terraform-oci-compartment module. (#3)
- `compartment_ids` and `compartment_paths` outputs for the tree, and
  `compartment_path` for the baseline compartment. (#3)
- `quota_statements` and `quota_name` inputs: one `oci_limits_quota` policy in
  the tenancy, with `{compartment}` and `{compartments.<key>}` replaced by
  compartment name paths. Empty by default, so no quota is created. (#3)
- `parent_compartment_path` input, needed for quota paths and the nesting
  check when the parent is not the tenancy. (#3)
- `quota_id` output. (#3)

### Changed

- `compartment_name` must be 1-100 letters, digits, periods, hyphens or
  underscores, and `compartment_description` 1-400 characters, checked at
  plan time instead of failing at apply. (#3)

## [1.2.0] - 2026-11-07

### Added

- `tag_defaults` input: creates `oci_identity_tag_default` resources on the
  baseline compartment for tags from `tag_keys`, with optional `is_required`.
  Empty by default, so existing plans are unchanged. (#4)
- `tag_default_ids` output: map of tag key name to tag default OCID. (#4)
- `budget_alerts` input: several budget alert rules, each `ACTUAL` or
  `FORECAST`, with its own threshold and optional recipients. (#5)
- `budget_alert_rule_ids` output: map of `budget_alerts` key to alert rule
  OCID. (#5)

### Changed

- The default plan now adds a `FORECAST` alert at 100% next to the existing
  `ACTUAL` alert at 80%. The existing rule moves from
  `oci_budget_alert_rule.this` to `oci_budget_alert_rule.this["actual"]` via a
  `moved` block, with the same type, threshold, recipients and message. (#5)

### Deprecated

- `budget_alert_threshold` (now defaults to `null`): when set, it overrides the
  threshold of the `actual` alert. Use `budget_alerts`. (#5)
- `budget_alert_rule_id` output: returns the `actual` alert rule OCID or
  `null`. Use `budget_alert_rule_ids`. (#5)

[Unreleased]: https://github.com/moveeeax/terraform-oci-baseline/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/moveeeax/terraform-oci-baseline/compare/v1.1.0...v1.2.0
