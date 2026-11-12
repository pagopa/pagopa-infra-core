resource "azurerm_resource_group" "carbon" {
  name     = "${local.project}-fe-rg"
  location = var.location

  tags = module.tag_config.tags
}

module "carbon_cdn" {
  source = "./.terraform/modules/__v4__/cdn_frontdoor_multiple"

  resource_group_name        = azurerm_resource_group.carbon.name
  location                   = var.location
  log_analytics_workspace_id = data.azurerm_log_analytics_workspace.log_analytics.id
  tenant_id                  = data.azurerm_client_config.current.tenant_id

  # CDN Profile
  profile = {
    name = local.project
  }

  custom_domains = {
    "carbon.${var.env != "prod" ? "${var.env}." : ""}platform.pagopa.it" = {
      dns_zone_name                = local.platform_dns_zone_name
      dns_zone_resource_group_name = local.platform_dns_zone_resource_group_name
    }
  }

  storage_account = {
    enabled                  = true
    account_name             = "${local.project}fe"
    account_replication_type = contains(["d", "u"], var.env_short) ? "LRS" : "ZRS"
    index_document           = "index.html"
    error_404_document       = "index.html"
    origin_group             = "origin-group-carbon"
  }

  endpoints = {
    "web" = {
      name = "${local.project}-cdn-web"
    }
  }

  origin_groups = {
    "origin-group-carbon" = {
      description = "Static content pool for carbon CDN"
      members     = []
      # The storage account origin is wired automatically when the storage account is enabled and the origin group is specified.

      health_probe = {
        path                = "/"
        protocol            = "Https"
        request_type        = "GET"
        interval_in_seconds = 120
      }

      load_balancing = {
        sample_size                        = 4
        successful_samples_required        = 2
        additional_latency_in_milliseconds = 0
      }
    }
  }

  routes = {
    "web" = {
      endpoint               = "web"
      origin_group           = "origin-group-carbon"
      patterns               = ["/*"]
      protocols              = ["Http", "Https"]
      forwarding             = "MatchRequest"
      https_redirect         = true
      cache_behavior         = "IgnoreQueryString"
      custom_domains         = ["carbon.${var.env != "prod" ? "${var.env}." : ""}platform.pagopa.it"]
      rulesets               = ["CarbonGlobal"]
      enabled                = true
      link_to_default_domain = true
    }
  }
  rulesets = {
    "CarbonGlobal" = {
      description = "Carbon dashboard caching rules"
      rules = {
        # Data is written straight to the storage account by an external job, with no purge:
        # cap both the edge TTL and the browser TTL so new drops show up within minutes.
        "DataShortCache" = {
          order             = 1
          behavior_on_match = "Continue"

          conditions = [
            {
              type         = "url_path"
              operator     = "BeginsWith"
              match_values = ["data/"]
              negate       = false
              transforms   = ["Lowercase"]
            }
          ]
          actions = [
            {
              type                  = "cache"
              behavior              = "Override"
              duration              = "00:05:00"
              query_string_behavior = "IgnoreQueryString"
            },
            {
              type          = "response_header"
              header_action = "Overwrite"
              header_name   = "Cache-Control"
              value         = "public, max-age=300"
            }
          ]
        }
      }
    }
  }

  enable_diagnostic_setting = false
  tags                      = module.tag_config.tags
}