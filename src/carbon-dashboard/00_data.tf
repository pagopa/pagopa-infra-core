data "azurerm_log_analytics_workspace" "log_analytics" {
  name                = local.log_analytics_workspace_name
  resource_group_name = local.log_analytics_workspace_resource_group_name
}

data "azurerm_dns_zone" "platform" {
  name                = local.platform_dns_zone_name
  resource_group_name = local.platform_dns_zone_resource_group_name
}