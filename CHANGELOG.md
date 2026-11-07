# Changelog

All notable changes to this module are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the module uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

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
