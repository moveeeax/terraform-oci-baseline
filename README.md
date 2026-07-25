# terraform-oci-baseline

Terraform module that provisions a small [Oracle Cloud Infrastructure](https://www.oracle.com/cloud/)
landing-zone baseline: a dedicated compartment, a governance defined-tag namespace with a
set of standard tag keys, and a monthly budget with a threshold alert scoped to the new
compartment. Use it as the first step when onboarding a new team or environment.

## Usage

```hcl
module "baseline" {
  source = "github.com/moveeeax/terraform-oci-baseline"

  tenancy_id            = var.tenancy_id
  parent_compartment_id = var.tenancy_id
  compartment_name      = "team-alpha"
  tag_namespace_name    = "alpha-governance"

  budget_amount           = 1000
  budget_alert_threshold  = 90
  budget_alert_recipients = "finops@example.com"

  freeform_tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
```

A runnable example lives in [`examples/basic`](examples/basic).

## Defaults worth knowing

- **The compartment is not really deleted on `terraform destroy`.**
  `compartment_enable_delete` defaults to `false` (the OCI provider default), so a
  destroy releases the compartment from state and leaves it in place. A landing-zone
  compartment is the blast-radius boundary for everything a team owns. Set it to
  `true` only for throwaway environments.
- **The budget alert must have a recipient.** `recipients` is optional in the OCI
  API, so a blank value creates an alert rule that fires and notifies nobody. The
  module rejects an empty or non-email `budget_alert_recipients` rather than
  shipping a budget that looks configured but is silent. Whitespace and empty
  entries in the list are trimmed before the value reaches the API.
- **`CostCenter` is created as a cost-tracking tag.** OCI Cost Analysis and
  `TAG`-targeted budgets only aggregate spend on tags explicitly flagged as
  cost-tracking; the API default is `false`. Without the flag the `CostCenter` key
  this module creates is invisible to every cost report — a cost-allocation tag
  that cannot allocate cost. Adjust with `cost_tracking_tag_keys` (OCI allows at
  most 10 cost-tracking tags per tenancy).

## Tests

```
terraform test
```

The suite in [`tests/`](tests) runs against a mocked OCI provider, so it needs no
credentials and no network. It requires Terraform >= 1.7 for `mock_provider`; the
module itself still supports >= 1.5.

## Requirements

| Name      | Version  |
|-----------|----------|
| terraform | >= 1.5   |
| oci       | >= 5.0   |

## Inputs

| Name                      | Description                                                        | Type           | Default                            | Required |
|---------------------------|--------------------------------------------------------------------|----------------|------------------------------------|:--------:|
| `tenancy_id`              | OCID of the tenancy the baseline is created under.                 | `string`       | n/a                                |   yes    |
| `parent_compartment_id`   | OCID of the parent compartment for the new compartment.            | `string`       | n/a                                |   yes    |
| `compartment_name`        | Name of the landing-zone compartment.                             | `string`       | n/a                                |   yes    |
| `compartment_description` | Description of the landing-zone compartment.                       | `string`       | landing-zone default               |    no    |
| `compartment_enable_delete` | Whether `terraform destroy` really deletes the compartment.      | `bool`         | `false`                            |    no    |
| `tag_namespace_name`      | Name of the defined-tag namespace.                                | `string`       | n/a                                |   yes    |
| `tag_keys`                | Defined-tag keys to create in the namespace.                      | `list(string)` | `["Environment","Owner","CostCenter"]` |  no  |
| `cost_tracking_tag_keys`  | Keys from `tag_keys` to mark as cost-tracking (max 10).           | `list(string)` | `["CostCenter"]`                   |    no    |
| `budget_amount`           | Monthly budget amount tracking the compartment.                   | `number`       | `100`                              |    no    |
| `budget_alert_threshold`  | Budget percentage at which the alert notifies.                    | `number`       | `80`                               |    no    |
| `budget_alert_recipients` | Comma-separated email recipients for the budget alert (>= 1).     | `string`       | n/a                                |   yes    |
| `freeform_tags`           | Free-form tags applied to the baseline resources.                 | `map(string)`  | `{}`                               |    no    |
| `defined_tags`            | Defined tags applied to the baseline resources.                   | `map(string)`  | `{}`                               |    no    |

## Outputs

| Name                   | Description                              |
|------------------------|------------------------------------------|
| `compartment_id`       | OCID of the landing-zone compartment.    |
| `tag_namespace_id`     | OCID of the governance tag namespace.    |
| `tag_ids`              | Map of tag key name to tag OCID.         |
| `budget_id`            | OCID of the compartment budget.          |
| `budget_alert_rule_id` | OCID of the budget alert rule.           |

## License

[MIT](LICENSE)
