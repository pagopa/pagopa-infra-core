
<!-- markdownlint-disable -->
<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_azapi"></a> [azapi](#requirement\_azapi) | <= 1.3.0 |
| <a name="requirement_azuread"></a> [azuread](#requirement\_azuread) | <= 2.6.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | = 2.99.0 |
| <a name="requirement_local"></a> [local](#requirement\_local) | <= 2.3.0 |
| <a name="requirement_null"></a> [null](#requirement\_null) | <= 3.2.1 |
| <a name="requirement_random"></a> [random](#requirement\_random) | <= 3.4.3 |
| <a name="requirement_time"></a> [time](#requirement\_time) | <= 0.11.1 |
| <a name="requirement_tls"></a> [tls](#requirement\_tls) | <= 4.0.5 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_apim_payment_manager_product"></a> [apim\_payment\_manager\_product](#module\_apim\_payment\_manager\_product) | git::https://github.com/pagopa/azurerm.git//api_management_product | v1.0.90 |
| <a name="module_apim_pm_per_nodo_v1"></a> [apim\_pm\_per\_nodo\_v1](#module\_apim\_pm\_per\_nodo\_v1) | git::https://github.com/pagopa/azurerm.git//api_management_api | v1.0.90 |
| <a name="module_apim_pm_per_nodo_v2"></a> [apim\_pm\_per\_nodo\_v2](#module\_apim\_pm\_per\_nodo\_v2) | git::https://github.com/pagopa/azurerm.git//api_management_api | v1.0.90 |
| <a name="module_tag_config"></a> [tag\_config](#module\_tag\_config) | ../tag_config | n/a |

## Resources

| Name | Type |
|------|------|
| [azurerm_api_management_api_operation_policy.send_payment_result_api_v2_wisp_policy](https://registry.terraform.io/providers/hashicorp/azurerm/2.99.0/docs/resources/api_management_api_operation_policy) | resource |
| [azurerm_api_management_api_version_set.pm_per_nodo_api](https://registry.terraform.io/providers/hashicorp/azurerm/2.99.0/docs/resources/api_management_api_version_set) | resource |
| [terraform_data.sha256_send_payment_result_api_v2_wisp_policy](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [azurerm_api_management.apim_migrated](https://registry.terraform.io/providers/hashicorp/azurerm/2.99.0/docs/data-sources/api_management) | data source |
| [azurerm_application_insights.application_insights](https://registry.terraform.io/providers/hashicorp/azurerm/2.99.0/docs/data-sources/application_insights) | data source |
| [azurerm_client_config.current](https://registry.terraform.io/providers/hashicorp/azurerm/2.99.0/docs/data-sources/client_config) | data source |
| [azurerm_resource_group.monitor_rg](https://registry.terraform.io/providers/hashicorp/azurerm/2.99.0/docs/data-sources/resource_group) | data source |
| [azurerm_resource_group.rg_api](https://registry.terraform.io/providers/hashicorp/azurerm/2.99.0/docs/data-sources/resource_group) | data source |
| [azurerm_resource_group.rg_vnet](https://registry.terraform.io/providers/hashicorp/azurerm/2.99.0/docs/data-sources/resource_group) | data source |
| [azurerm_subscription.current](https://registry.terraform.io/providers/hashicorp/azurerm/2.99.0/docs/data-sources/subscription) | data source |
| [azurerm_virtual_network.vnet](https://registry.terraform.io/providers/hashicorp/azurerm/2.99.0/docs/data-sources/virtual_network) | data source |
| [azurerm_virtual_network.vnet_integration](https://registry.terraform.io/providers/hashicorp/azurerm/2.99.0/docs/data-sources/virtual_network) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_create_wisp_converter"></a> [create\_wisp\_converter](#input\_create\_wisp\_converter) | CREATE WISP dismantling system infra | `bool` | `false` | no |
| <a name="input_dns_zone_prefix"></a> [dns\_zone\_prefix](#input\_dns\_zone\_prefix) | The dns subdomain. | `string` | `null` | no |
| <a name="input_ecommerce_ingress_hostname"></a> [ecommerce\_ingress\_hostname](#input\_ecommerce\_ingress\_hostname) | ecommerce ingress hostname | `string` | `null` | no |
| <a name="input_env"></a> [env](#input\_env) | Contains env description in extend format (dev,uat,prod) | `string` | n/a | yes |
| <a name="input_env_short"></a> [env\_short](#input\_env\_short) | Environment shot version | `string` | n/a | yes |
| <a name="input_external_domain"></a> [external\_domain](#input\_external\_domain) | Domain for delegation | `string` | `null` | no |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | n/a | `string` | `"pagopa"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_application_insights_instrumentation_key"></a> [application\_insights\_instrumentation\_key](#output\_application\_insights\_instrumentation\_key) | n/a |
| <a name="output_vnet_address_space"></a> [vnet\_address\_space](#output\_vnet\_address\_space) | n/a |
| <a name="output_vnet_id"></a> [vnet\_id](#output\_vnet\_id) | n/a |
| <a name="output_vnet_integration_address_space"></a> [vnet\_integration\_address\_space](#output\_vnet\_integration\_address\_space) | n/a |
| <a name="output_vnet_integration_name"></a> [vnet\_integration\_name](#output\_vnet\_integration\_name) | n/a |
| <a name="output_vnet_name"></a> [vnet\_name](#output\_vnet\_name) | n/a |
<!-- END_TF_DOCS -->
