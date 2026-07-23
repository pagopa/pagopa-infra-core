data "azurerm_resource_group" "monitor_rg" {
  name = format("%s-monitor-rg", local.project)
}

data "azurerm_application_insights" "application_insights" {
  name                = format("%s-appinsights", local.project)
  resource_group_name = data.azurerm_resource_group.monitor_rg.name
}


data "azurerm_log_analytics_workspace" "log_analytics_workspace" {
  name                = format("%s-law", local.project)
  resource_group_name = data.azurerm_resource_group.monitor_rg.name
}



data "azurerm_monitor_action_group" "email" {
  name                = "PagoPA"
  resource_group_name = data.azurerm_resource_group.monitor_rg.name
}


