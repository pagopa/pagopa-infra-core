locals {
  product        = "${var.prefix}-${var.env_short}"
  product_region = "${var.prefix}-${var.env_short}-${var.location_short}"
  project        = "${var.prefix}-${var.env_short}-${var.location_short}-${var.domain}"

  location_acr_backup       = "germanywestcentral"
  dns_forwarder_backup_name = "${local.product}-dns-forwarder-backup-vmss"

  azdo_iac_managed_identities   = toset(["azdo-${var.env}-pagopa-iac-deploy", "azdo-${var.env}-pagopa-iac-plan"])
  azdo_managed_identity_rg_name = "pagopa-${var.env_short}-identity-rg"

}
