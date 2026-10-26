module "vm_icinga_subnet" {
  source = "./.terraform/modules/__v4__/IDH/subnet"

  env               = var.env
  idh_resource_tier = "slash28_privatelink_true"
  name              = "${local.project}-spoke-tools-vm-icinga-snet"
  product_name      = local.prefix

  resource_group_name  = local.vnet_tools_rg
  virtual_network_name = local.vnet_tools_name

  # custom_nsg_configuration = {
  #   target_service               = "eventhub"
  #   source_address_prefixes_name = "All"
  #   source_address_prefixes      = ["*"]
  # }

  tags = module.tag_config.tags
}