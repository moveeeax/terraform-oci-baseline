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
