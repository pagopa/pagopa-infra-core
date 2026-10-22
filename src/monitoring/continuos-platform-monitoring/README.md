<!-- markdownlint-disable -->
<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0 |
| <a name="requirement_azapi"></a> [azapi](#requirement\_azapi) | >= 2.13.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 5 |
| <a name="requirement_icinga2"></a> [icinga2](#requirement\_icinga2) | = 0.7.1 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_tag_config"></a> [tag\_config](#module\_tag\_config) | ../../tag_config | n/a |

## Resources

| Name | Type |
|------|------|
| [azurerm_virtual_machine_run_command.icinga_bp](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_machine_run_command) | resource |
| [icinga2_host.azure_hosts](https://registry.terraform.io/providers/Icinga/icinga2/0.7.1/docs/resources/host) | resource |
| [icinga2_service.azure_services](https://registry.terraform.io/providers/Icinga/icinga2/0.7.1/docs/resources/service) | resource |
| [terraform_data.azure_hosts_config](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.azure_services_config](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [azapi_resource.this](https://registry.terraform.io/providers/azure/azapi/latest/docs/data-sources/resource) | data source |
| [azapi_resource_action.provider](https://registry.terraform.io/providers/azure/azapi/latest/docs/data-sources/resource_action) | data source |
| [azapi_resource_list.afd_endpoints](https://registry.terraform.io/providers/azure/azapi/latest/docs/data-sources/resource_list) | data source |
| [azapi_resource_list.afd_routes](https://registry.terraform.io/providers/azure/azapi/latest/docs/data-sources/resource_list) | data source |
| [azapi_resource_list.children](https://registry.terraform.io/providers/azure/azapi/latest/docs/data-sources/resource_list) | data source |
| [azurerm_key_vault.core](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/key_vault) | data source |
| [azurerm_key_vault_secret.metabase_psw](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/key_vault_secret) | data source |
| [azurerm_key_vault_secret.metabase_usr](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/key_vault_secret) | data source |
| [azurerm_resources.sub_resources](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/resources) | data source |
| [azurerm_subscription.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/subscription) | data source |
| [azurerm_virtual_machine.icinga](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/virtual_machine) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_env"></a> [env](#input\_env) | n/a | `string` | n/a | yes |
| <a name="input_env_short"></a> [env\_short](#input\_env\_short) | n/a | `string` | n/a | yes |
| <a name="input_location_short"></a> [location\_short](#input\_location\_short) | One of wue, neu | `string` | n/a | yes |

## Outputs

No outputs.
<!-- END_TF_DOCS -->
