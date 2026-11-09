data "azurerm_resource_group" "resource_group" {
  name = "${local.product}-azdoa-rg"
}


module "azdoa_custom_image" {
  source = "./.terraform/modules/__v4__/azure_devops_agent_custom_image"

  resource_group_name = data.azurerm_resource_group.resource_group.name
  location            = var.location
  image_name          = "${local.product}-azdo-agent-ubuntu2204-image"
  image_version       = var.azdo_agent_image_version
  subscription_id     = data.azurerm_subscription.current.subscription_id
}

module "azuredevops_custom_image" {
  source = "./.terraform/modules/__v4__/azure_vm_custom_image"

  location              = var.location
  resource_group_name   = data.azurerm_resource_group.resource_group.name
  subscription_id       = data.azurerm_subscription.current.subscription_id
  image_name            = "${local.product}-azdo-agent-ubuntu2404-image"
  image_version         = var.azuredevops_agent_image_version
  base_image_offer      = "ubuntu-24_04-lts"
  script_custom_content = "../../../../../templates/script-custom.sh"
}