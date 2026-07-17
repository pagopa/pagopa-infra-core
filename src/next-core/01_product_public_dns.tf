/*
 * Product Public DNS Zones Configuration
 *
 * This module manages public DNS zones for PagoPA products.
 *
 * How to add a zone to org infra: https://pagopa.atlassian.net/wiki/spaces/DEVOPS/pages/426214700/Azure+-+DNS+deleghe+sotto+domini+per+prodotto
 *
 * HOW TO ADD A NEW PRODUCT DNS ZONE:
 *
 * 1. Add a new entry in the 'products_dns_zones' local map with the product name as key:
 *    "product-name" = {
 *      dev_delegation_records = []
 *      uat_delegation_records = []
 *    }
 *
 * 2. DNS Zone naming convention:
 *    - DEV: dev.product-name.pagopa.it
 *    - UAT: uat.product-name.pagopa.it
 *    - PROD: product-name.pagopa.it
 *
 * 3. Configure delegation records (PROD environment ONLY):
 *    After creating DNS zones in DEV and UAT, add their nameservers to enable delegation:
 *    dev_delegation_records = [
 *      "ns1-01.azure-dns.com.",
 *      "ns2-01.azure-dns.net.",
 *      "ns3-01.azure-dns.org.",
 *      "ns4-01.azure-dns.info."
 *    ]
 *    uat_delegation_records = [
 *      "ns1-02.azure-dns.com.",
 *      ...
 *    ]
 *
 * 4. Configure DNS records in var.product_dns_records (99_variables.tf):
 *    Add product-specific DNS records configuration:
 *
 *    "product-name" = {
 *      # Email settings for AWS SES
 *      # every field is optional and can be omitted
 *      email_settings = {
 *        amazonses_record = "token-from-aws-ses-verification"     # Amazon SES domain verification token
 *        mx_record        = "feedback-smtp.eu-south-1.amazonses.com"  # Amazon SES SMTP endpoint
 *        spf_record       = "v=spf1 include:amazonses.com -all"   # SPF record for email authentication
 *        bimi_record      = "v=BIMI1; l=https://...; a=https://..." # BIMI record for brand indicators
 *        dmarc_record     = "v=DMARC1; p=reject; rua=mailto:..."  # DMARC policy
 *        dkim_records = [                                          # DKIM records for email signing
 *          {
 *            "r_name"  = "selector1._domainkey"
 *            "r_value" = "selector1.dkim.eu-south-1.amazonses.com"
 *          },
 *          {
 *            "r_name"  = "selector2._domainkey"
 *            "r_value" = "selector2.dkim.eu-south-1.amazonses.com"
 *          },
 *          ...
 *        ]
 *      }
 *
 *      # Additional TXT records
 *      txt_records = [
 *        {
 *          "r_name"  = "record-name"           # Name of the TXT record
 *          "r_value" = "record-value"          # Value of the TXT record
 *        },
 *        ...
 *      ]
 *
 *      # Additional MX records
 *      mx_records = [
 *        {
 *          "r_name"  = "record-name"           # Name of the MX record
 *          "r_value" = "mail.example.com"      # Mail server address
 *        },
 *        ...
 *      ]
 *    }
 *
 *    Email settings create:
 *    - TXT record at: _amazonses.product-name.pagopa.it (for SES verification)
 *    - CNAME records for DKIM: selector._domainkey.product-name.pagopa.it
 *    - MX record at: email.product-name.pagopa.it
 *    - SPF TXT record at: email.product-name.pagopa.it
 *    - BIMI TXT record at: default._bimi.product-name.pagopa.it
 *    - DMARC TXT record at: _dmarc.product-name.pagopa.it
 *
 * 5. Leave arrays/maps empty if not needed:
 *    - Empty dev_delegation_records = [] → no DEV delegation created
 *    - Empty uat_delegation_records = [] → no UAT delegation created
 *    - Empty email_settings = {} → no email records created
 *    - Empty txt_records = [] → no additional TXT records created
 *    - Empty mx_records = [] → no additional MX records created
 *
 * RESOURCES CREATED:
 * - azurerm_dns_zone: DNS zone for each product (all environments)
 * - azurerm_dns_ns_record: NS delegation records for DEV and UAT (PROD only)
 * - azurerm_dns_txt_record: Amazon SES verification, SPF, BIMI, DMARC and additional TXT records
 * - azurerm_dns_cname_record: DKIM records for AWS SES (PROD only)
 * - azurerm_dns_mx_record: MX record for email and additional MX records
 */

locals {
  products_dns_zones = {
    "ricevute" = {
      # todo delegation records after create DNS zone in DEV env
      dev_delegation_records = [
        "ns1-05.azure-dns.com.",
        "ns2-05.azure-dns.net.",
        "ns3-05.azure-dns.org.",
        "ns4-05.azure-dns.info."
      ]
      # todo delegation records after create DNS zone in UAT env
      uat_delegation_records = [
        "ns1-09.azure-dns.com.",
        "ns2-09.azure-dns.net.",
        "ns3-09.azure-dns.org.",
        "ns4-09.azure-dns.info."
      ]
    },
    "internal-apps.platform" = {
      dev_delegation_records = [
        "ns1-03.azure-dns.com.",
        "ns2-03.azure-dns.net.",
        "ns3-03.azure-dns.org.",
        "ns4-03.azure-dns.info."
      ]
      uat_delegation_records = [
        "ns1-06.azure-dns.com.",
        "ns2-06.azure-dns.net.",
        "ns3-06.azure-dns.org.",
        "ns4-06.azure-dns.info."
      ]
    },
  }
}

locals {
  dev_products   = { for k, v in local.products_dns_zones : k => v.dev_delegation_records if length(v.dev_delegation_records) != 0 }
  uat_products   = { for k, v in local.products_dns_zones : k => v.uat_delegation_records if length(v.uat_delegation_records) != 0 }
  email_products = { for k, v in var.product_dns_records : k => v.email_settings if length(v.email_settings) != 0 }
  txt_records_flattened = {
    for item in flatten([
      for product, settings in var.product_dns_records : [
        for txt in settings.txt_records : {
          key   = "${product}#txt#${txt.r_name}"
          value = txt
        }
      ] if length(settings.txt_records) > 0
    ]) : item.key => item.value
  }
  mx_records_flattened = {
    for item in flatten([
      for product, settings in var.product_dns_records : [
        for mx in settings.mx_records : {
          key   = "${product}#mx#${mx.r_name}"
          value = mx
        }
      ] if length(settings.mx_records) > 0
    ]) : item.key => item.value
  }
  email_dkim_flattened = {
    for item in flatten([
      for product, settings in var.product_dns_records : [
        for dkim in settings.email_settings.dkim_records : {
          key   = "${product}#${dkim.r_name}"
          value = dkim
        }
      ] if settings.email_settings != {}
    ]) : item.key => item.value
  }
}

output "test" {
  value = local.txt_records_flattened
}

resource "azurerm_dns_zone" "public_product_dns_zone" {
  for_each            = local.products_dns_zones
  name                = join(".", var.env_short == "p" ? [each.key, var.external_domain] : [var.env, each.key, var.external_domain])
  resource_group_name = azurerm_resource_group.rg_vnet.name
  tags                = module.tag_config.tags
}


# Prod ONLY record to DEV public DNS delegation
resource "azurerm_dns_ns_record" "dev_product_dns_zone_delegation" {
  for_each            = var.env_short == "p" ? local.dev_products : {}
  name                = "dev"
  zone_name           = azurerm_dns_zone.public_product_dns_zone[each.key].name
  resource_group_name = azurerm_resource_group.rg_vnet.name
  records             = each.value
  ttl                 = var.dns_default_ttl_sec
  tags                = module.tag_config.tags
}


# Prod ONLY record to UAT public DNS delegation
resource "azurerm_dns_ns_record" "uat_product_dns_zone_delegation" {
  for_each            = var.env_short == "p" ? local.uat_products : {}
  name                = "uat"
  zone_name           = azurerm_dns_zone.public_product_dns_zone[each.key].name
  resource_group_name = azurerm_resource_group.rg_vnet.name
  records             = each.value
  ttl                 = var.dns_default_ttl_sec
  tags                = module.tag_config.tags
}


# EMAIL RECORDS
resource "azurerm_dns_txt_record" "aws_ses_dns_txt_record" {
  for_each            = { for epk, epv in local.email_products : epk => epv if epv.amazonses_record != null }
  name                = "_amazonses"
  zone_name           = azurerm_dns_zone.public_product_dns_zone[each.key].name
  resource_group_name = azurerm_resource_group.rg_vnet.name
  ttl                 = var.dns_default_ttl_sec
  record {
    value = each.value.amazonses_record
  }
  tags = module.tag_config.tags
}

resource "azurerm_dns_cname_record" "dkim_aws_ses_dns_cname_record" {
  for_each            = local.email_dkim_flattened
  name                = each.value.r_name
  zone_name           = azurerm_dns_zone.public_product_dns_zone[split("#", each.key)[0]].name
  resource_group_name = azurerm_resource_group.rg_vnet.name
  ttl                 = var.dns_default_ttl_sec
  record              = each.value.r_value
  tags                = module.tag_config.tags
}

resource "azurerm_dns_mx_record" "email_dns_mx_record" {
  for_each            = { for epk, epv in local.email_products : epk => epv if epv.mx_record != null }
  name                = "email"
  zone_name           = azurerm_dns_zone.public_product_dns_zone[each.key].name
  resource_group_name = azurerm_resource_group.rg_vnet.name
  ttl                 = var.dns_default_ttl_sec

  record {
    preference = 10
    exchange   = each.value.mx_record
  }

  tags = module.tag_config.tags
}

# spf record
resource "azurerm_dns_txt_record" "email_dns_txt_spf_record" {
  for_each            = { for epk, epv in local.email_products : epk => epv if epv.spf_record != null }
  name                = "email"
  zone_name           = azurerm_dns_zone.public_product_dns_zone[each.key].name
  resource_group_name = azurerm_resource_group.rg_vnet.name
  ttl                 = var.dns_default_ttl_sec
  record {
    value = each.value.spf_record
  }
  tags = module.tag_config.tags
}

# bimi record

resource "azurerm_dns_txt_record" "email_dns_txt_bimi_record" {
  for_each            = { for epk, epv in local.email_products : epk => epv if epv.bimi_record != null }
  name                = "default._bimi"
  zone_name           = azurerm_dns_zone.public_product_dns_zone[each.key].name
  resource_group_name = azurerm_resource_group.rg_vnet.name
  ttl                 = var.dns_default_ttl_sec_short
  record {
    value = each.value.bimi_record
  }
  tags = module.tag_config.tags
}

resource "azurerm_dns_txt_record" "email_dns_txt_dmarc_record" {
  for_each            = { for epk, epv in local.email_products : epk => epv if epv.dmarc_record != null }
  name                = "_dmarc"
  zone_name           = azurerm_dns_zone.public_product_dns_zone[each.key].name
  resource_group_name = azurerm_resource_group.rg_vnet.name
  ttl                 = var.dns_default_ttl_sec_short
  record {
    value = each.value.dmarc_record
  }
  tags = module.tag_config.tags
}


# additional txt records
resource "azurerm_dns_txt_record" "additional_txt_record" {
  for_each            = local.txt_records_flattened
  name                = each.value.r_name
  zone_name           = azurerm_dns_zone.public_product_dns_zone[split("#", each.key)[0]].name
  resource_group_name = azurerm_resource_group.rg_vnet.name
  ttl                 = var.dns_default_ttl_sec
  record {
    value = each.value.r_value
  }
  tags = module.tag_config.tags
}

# additional mx records
resource "azurerm_dns_mx_record" "additional_mx_record" {
  for_each            = local.mx_records_flattened
  name                = each.value.r_name
  zone_name           = azurerm_dns_zone.public_product_dns_zone[split("#", each.key)[0]].name
  resource_group_name = azurerm_resource_group.rg_vnet.name
  ttl                 = var.dns_default_ttl_sec
  record {
    preference = 10
    exchange   = each.value.r_value
  }
  tags = module.tag_config.tags
}

