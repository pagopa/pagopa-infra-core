<!-- markdownlint-disable -->
<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 5 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module___v4__"></a> [\_\_v4\_\_](#module\_\_\_v4\_\_) | git::https://github.com/pagopa/terraform-azurerm-v4 | 49d12bd64b144b516f104fb50683b432f1c798ef |
| <a name="module_amba_alerts_core_platform"></a> [amba\_alerts\_core\_platform](#module\_amba\_alerts\_core\_platform) | ./.terraform/modules/__v4__/continuos_platform_alerting | n/a |
| <a name="module_tag_config"></a> [tag\_config](#module\_tag\_config) | ../tag_config | n/a |

## Resources

| Name | Type |
|------|------|
| [azurerm_client_config.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |
| [azurerm_resources.all_ag](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/resources) | data source |
| [azurerm_subscription.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/subscription) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_domain"></a> [domain](#input\_domain) | n/a | `string` | n/a | yes |
| <a name="input_env"></a> [env](#input\_env) | n/a | `string` | n/a | yes |
| <a name="input_env_short"></a> [env\_short](#input\_env\_short) | n/a | `string` | n/a | yes |
| <a name="input_location_short"></a> [location\_short](#input\_location\_short) | One of wue, neu | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_riepilogo_alert"></a> [riepilogo\_alert](#output\_riepilogo\_alert) | n/a |
<!-- END_TF_DOCS -->
