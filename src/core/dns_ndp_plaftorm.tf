## AWS SES Service ##




# MX record for sub domain ndp
resource "azurerm_dns_mx_record" "dns-mx-ndp-platform-pagopa-it" {
  count               = var.env_short == "p" ? 1 : 0
  name                = "ndp"                                # ndp.platform.pagopa.it
  zone_name           = data.azurerm_dns_zone.public[0].name # platform.pagopa.it
  resource_group_name = data.azurerm_resource_group.rg_vnet.name
  ttl                 = var.dns_default_ttl_sec

  record {
    preference = 10
    exchange   = "feedback-smtp.eu-south-1.amazonses.com"
  }

  tags = module.tag_config.tags
}

# TXT record
resource "azurerm_dns_txt_record" "dns-txt-ndp-platform-pagopa-it-aws-ses-txt" {
  count               = var.env_short == "p" ? 1 : 0
  name                = "ndp"                                # ndp.platform.pagopa.it
  zone_name           = data.azurerm_dns_zone.public[0].name # platform.pagopa.it
  resource_group_name = data.azurerm_resource_group.rg_vnet.name
  ttl                 = var.dns_default_ttl_sec
  record {
    value = "v=spf1 include:amazonses.com ~all"
  }
  tags = module.tag_config.tags
}
