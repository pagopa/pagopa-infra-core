locals {
  # ---------------------------------------------------------------------------
  # General
  # ---------------------------------------------------------------------------
  prefix               = "pagopa"
  domain               = "cpm"
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

  # identifies the Icinga configuration run, see 00_vm.tf
  icinga_configure_hash = substr(sha256(jsonencode([
    filesha256("${path.module}/templates/icinga-configure.sh"),
    data.azurerm_key_vault_secret.icingadb_db_password.version,
    data.azurerm_key_vault_secret.icingaweb_db_password.version,
    data.azurerm_key_vault_secret.icingaweb_admin_password.version,
    data.azurerm_key_vault_secret.icinga_api_terraform_password.version,
  ])), 0, 8)
}
