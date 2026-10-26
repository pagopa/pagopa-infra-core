locals {
  # ---------------------------------------------------------------------------
  # General
  # ---------------------------------------------------------------------------
  prefix               = "pagopa"
  domain               = "core"
  location_short       = "itn"
  product              = "${local.prefix}-${var.env_short}"
  project              = "${local.product}-${var.location_short}-${local.domain}"
  location             = "italynorth"
  icinga_image_version = "v3"

  # ---------------------------------------------------------------------------
  # Icinga VM
  # ---------------------------------------------------------------------------
  icinga_vm_size = "Standard_B2ms"

  vnet_tools_name = "${local.product}-${local.location_short}-spoke-tools-vnet"
  vnet_tools_rg   = "${local.product}-${local.location_short}-network-hub-spoke-rg"
}
