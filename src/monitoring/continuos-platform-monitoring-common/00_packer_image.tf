resource "azurerm_resource_group" "custom_image_rg" {
  name     = "${local.project}-icinga-monitoring-rg"
  location = local.location

  tags = module.tag_config.tags
}


module "azure_custom_image" {
  source                = "./.terraform/modules/__v4__/azure_vm_custom_image"
  resource_group_name   = azurerm_resource_group.custom_image_rg.name
  location              = local.location
  image_name            = "${local.product}-icinga-ubuntu2604-image"
  image_version         = local.icinga_image_version
  script_custom_content = "../../../../../templates/script-custom.sh"
  subscription_id       = data.azurerm_subscription.current.subscription_id


}