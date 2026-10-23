locals {
  # ---------------------------------------------------------------------------
  # General
  # ---------------------------------------------------------------------------
  prefix                             = "pagopa"
  domain                             = "core"
  product                            = "${local.prefix}-${var.env_short}"
  project                            = "${local.product}-${var.location_short}-${local.domain}"
  core_key_vault_name                = "${local.project}-kv"
  core_key_vault_resource_group_name = "${local.project}-sec-rg"
  location                           = "italynorth"
  icinga_image_version  = "v1"
}
