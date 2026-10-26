locals {
  prefix         = "pagopa"
  domain         = "cpm"
  location       = "italynorth"
  location_short = "itn"
  input_file     = "./secret/${var.env}/configs.json"

  project = "${local.prefix}-${var.env_short}-${local.location_short}-${local.domain}"
  product = "${local.prefix}-${var.env_short}"


  azdo_managed_identity_rg_name = "pagopa-${var.env_short}-identity-rg"
  azdo_iac_managed_identities   = toset(["azdo-${var.env}-pagopa-iac-deploy", "azdo-${var.env}-pagopa-iac-plan"])

}
