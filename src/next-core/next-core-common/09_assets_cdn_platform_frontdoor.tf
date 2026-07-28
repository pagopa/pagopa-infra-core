locals {
  # Origin allowlist for the self-hosted NPG SDK served from this CDN.
  #
  # Front Door cannot echo the incoming Origin back: the
  # Access-Control-Allow-Origin action value is a static string, so every allowed
  # origin needs its own rule.
  #
  # dev and uat frontends read /npg-uat/, prod reads /npg-prod/: see
  # npg_sdk_url in the .devops/pagopa-deploy-pipelines.yml of the three FEs.
  npg_sdk_cors_origins = [
    { order = 5, name = "AllowNpgSdkCORSCheckoutProd", path = "/npg-prod/", origin = "https://checkout.pagopa.it" },
    { order = 6, name = "AllowNpgSdkCORSEcommerceProd", path = "/npg-prod/", origin = "https://ecommerce.pagopa.it" },
    { order = 7, name = "AllowNpgSdkCORSWalletProd", path = "/npg-prod/", origin = "https://payment-wallet.pagopa.it" },
    { order = 8, name = "AllowNpgSdkCORSCheckoutUat", path = "/npg-uat/", origin = "https://uat.checkout.pagopa.it" },
    { order = 9, name = "AllowNpgSdkCORSEcommerceUat", path = "/npg-uat/", origin = "https://uat.ecommerce.pagopa.it" },
    { order = 10, name = "AllowNpgSdkCORSWalletUat", path = "/npg-uat/", origin = "https://uat.payment-wallet.pagopa.it" },
    { order = 11, name = "AllowNpgSdkCORSCheckoutDev", path = "/npg-uat/", origin = "https://dev.checkout.pagopa.it" },
    { order = 12, name = "AllowNpgSdkCORSEcommerceDev", path = "/npg-uat/", origin = "https://dev.ecommerce.pagopa.it" },
    { order = 13, name = "AllowNpgSdkCORSWalletDev", path = "/npg-uat/", origin = "https://dev.payment-wallet.pagopa.it" },
  ]

  npg_sdk_cors_rules = [
    for o in local.npg_sdk_cors_origins : {
      name              = o.name
      order             = o.order
      behavior_on_match = "Continue"

      url_path_conditions = [{
        operator         = "BeginsWith"
        match_values     = [o.path]
        negate_condition = false
        transforms       = ["Lowercase"]
      }]

      request_header_conditions = [{
        selector         = "Origin"
        operator         = "Equal"
        match_values     = [o.origin]
        negate_condition = false
        transforms       = []
      }]

      modify_response_header_actions = [{
        action = "Overwrite"
        name   = "Access-Control-Allow-Origin"
        value  = o.origin
      }]
    }
  ]
}

/**
 * Platform assets resource group
 **/
resource "azurerm_resource_group" "assets_cdn_platform_rg" {
  count    = var.env_short == "p" ? 1 : 0
  name     = format("%s-assets-cdn-platform-rg", local.product)
  location = var.location

  tags = module.tag_config.tags
}

/**
 * CDN
 */
module "assets_cdn_platform_frontdoor" {
  source = "./.terraform/modules/__v4__/cdn_frontdoor"
  count  = var.env_short == "p" ? 1 : 0

  cdn_prefix_name     = "${var.prefix}-${var.env_short}-assets-platform"
  location            = var.location
  resource_group_name = azurerm_resource_group.assets_cdn_platform_rg[0].name

  storage_account_error_404_document = "index.html"
  storage_account_index_document     = "index.html"
  storage_account_replication_type   = var.cdn_storage_account_replication_type
  querystring_caching_behaviour      = "UseQueryString"

  custom_domains = [
    {
      domain_name             = "assets.cdn.${azurerm_dns_zone.public[0].name}"
      dns_name                = azurerm_dns_zone.public[0].name
      dns_resource_group_name = azurerm_dns_zone.public[0].resource_group_name
      ttl                     = var.env != "p" ? 300 : 3600
    }
  ]

  global_delivery_rules = [{
    order = 1

    # HSTS
    modify_response_header_actions = [{
      action = "Overwrite"
      name   = "Strict-Transport-Security"
      value  = "max-age=31536000"
      },
      # Content-Security-Policy (in Report mode)
      # {
      #   action = "Overwrite"
      #   name   = "Content-Security-Policy-Report-Only"
      #   value  = format("default-src 'self'; connect-src 'self' https://api.%s.%s https://api-eu.mixpanel.com https://wisp2.pagopa.gov.it", var.dns_zone_prefix, var.external_domain)
      # }
    ]
  }]

  delivery_rule_redirects = [
    {
      name              = "GoTOIndex2"
      order             = 2
      behavior_on_match = "Continue"
      url_path_conditions = [{
        operator         = "Equal"
        match_values     = ["/"]
        negate_condition = false
        transforms       = []
      }]

      url_redirect_actions = [{
        redirect_type = "Found"
        protocol      = "MatchRequest"
        hostname      = "portal.pagopa.gov.it"
        path          = "/pda.html"
        fragment      = ""
        query_string  = ""
        }
      ]
    },
    {
      name              = "PdaPortaltoRoot"
      order             = 3
      behavior_on_match = "Continue"
      url_path_conditions = [{
        operator         = "Equal"
        match_values     = ["/pda-portal/admin/login"]
        negate_condition = false
        transforms       = []
      }]
      url_redirect_actions = [{
        redirect_type = "Found"
        protocol      = "MatchRequest"
        hostname      = "portal.pagopa.gov.it"
        path          = "/pda.html"
        fragment      = ""
        query_string  = ""
        }
      ]
    }
  ]

  delivery_rule_url_path_condition_cache_expiration_action = [
    {
      name  = "BypassCacheOnQueryString"
      order = 0

      query_string_conditions = [{
        operator         = "GreaterThan"
        match_values     = ["0"]
        negate_condition = false
        transforms       = []
      }]

      route_configuration_override = {
        cache_behavior = "DisableCache"
      }
    }
  ]

  delivery_custom_rules = concat(
    [
      {
        name              = "AllowFontCORS"
        order             = 4
        behavior_on_match = "Continue"

        url_file_extension_conditions = [{
          operator         = "Equal"
          match_values     = ["woff", "woff2", "ttf"]
          negate_condition = false
          transforms       = ["Lowercase"]
        }]

        modify_response_header_actions = [{
          action = "Overwrite"
          name   = "Access-Control-Allow-Origin"
          value  = "*"
        }]
      }
    ],
    # The NPG SDK is self-hosted here and consumed cross-origin by checkout-fe,
    # wallet-fe and ecommerce-fe with Subresource Integrity (crossorigin="anonymous").
    # Both hfsdk.js (the SRI <script>) and hfsdk.integrity.json (a runtime fetch())
    # need an Access-Control-Allow-Origin header, otherwise the browser blocks them
    # and, fail-closed, the SDK never loads. Unlike the fonts above, the consumers
    # are a known and closed set, so the header is restricted to their origins
    # instead of using a wildcard. Also scoped to the /npg-*/ folders, so the rest
    # of this shared CDN is left untouched. See local.npg_sdk_cors_origins.
    local.npg_sdk_cors_rules
  )

  log_analytics_workspace_id = azurerm_log_analytics_workspace.log_analytics_workspace.id

  tags = module.tag_config.tags
}

resource "azurerm_application_insights_web_test" "assets_cdn_platform_web_test" {
  count                   = var.env_short == "p" ? 1 : 0
  name                    = format("%s-assets-platform-web-test", local.product)
  location                = var.location
  resource_group_name     = azurerm_resource_group.monitor_rg.name
  application_insights_id = azurerm_application_insights.application_insights.id
  kind                    = "ping"
  frequency               = 300
  timeout                 = 10
  enabled                 = true
  geo_locations           = ["emea-nl-ams-azr"]

  configuration = <<XML
<WebTest Name="checkout_fe_web_test" Id="ABD48585-0831-40CB-9069-682EA6BB3583" Enabled="True" CssProjectStructure="" CssIteration="" Timeout="10" WorkItemIds=""
    xmlns="http://microsoft.com/schemas/VisualStudio/TeamTest/2010" Description="" CredentialUserName="" CredentialPassword="" PreAuthenticate="True" Proxy="default" StopOnError="False" RecordedResultFile="" ResultsLocale="">
    <Items>
        <Request Method="GET" Guid="a5f10126-e4cd-570d-961c-cea43999a200" Version="1.1" Url="https://assets.cdn.platform.pagopa.it/index.html" ThinkTime="0" Timeout="10" ParseDependentRequests="False" FollowRedirects="True" RecordResult="True" Cache="False" ResponseTimeGoal="0" Encoding="utf-8" ExpectedHttpStatusCode="200" ExpectedResponseUrl="" ReportingName="" IgnoreHttpStatusCode="False" />
    </Items>
</WebTest>
XML

}
