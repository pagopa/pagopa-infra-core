locals {
  project = "${var.prefix}-${var.env_short}"

  apim_x_node_product_id = "apim_for_node"

  pagopa_apim_migrated_name = "${local.project}-apim"
  pagopa_apim_migrated_rg   = "${local.project}-api-rg"

  vnet_ita_name                = "pagopa-${var.env_short}-itn-vnet"
  vnet_ita_resource_group_name = "pagopa-${var.env_short}-itn-vnet-rg"


}
