resource "azurerm_resource_group" "carbon" {
  name     = "${local.project}-monitor-rg"
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
    name = "${local.project}-carbon-profile"
  }

  storage_account = {
    enabled                  = true
    account_name             = "${local.project}carbonfe"
    account_replication_type = contains(["d", "u"], var.env_short) ? "LRS" : "ZRS"
    index_document           = "index.html"
    error_404_document       = "error.html"
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
      custom_domains         = []
      rulesets               = ["CarbonGlobal"]
      enabled                = true
      link_to_default_domain = true
    }
  }
  rulesets = {
    "CarbonGlobal" = {
      description = "SPA routing"
      rules = {
        "SPARewrite" = {
          order             = 1
          behavior_on_match = "Stop"

          conditions = [
            {
              type         = "url_path"
              operator     = "RegEx"
              match_values = ["^/(.*)$"]
              negate       = false
              transforms   = []
            }
          ]
          actions = [
            {
              type                    = "rewrite"
              source_pattern          = "/"
              destination             = "/index.html"
              preserve_unmatched_path = false
            }
          ]
        }
      }
    }
  }
  enable_diagnostic_setting = false
}