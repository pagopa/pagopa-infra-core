data "azurerm_resource_group" "rg_api" {
  name = format("%s-api-rg", local.project)
}

locals {
  api_domain = format("api.%s.%s", var.dns_zone_prefix, var.external_domain)
}

###########################
## Api Management (apim) ##
###########################

data "azurerm_api_management" "apim_migrated" {
  count               = 1
  name                = local.pagopa_apim_migrated_name
  resource_group_name = local.pagopa_apim_migrated_rg
}



