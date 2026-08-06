locals {
  project = "${var.prefix}-${var.env_short}-${var.location_short}-${var.domain}"
  product = "${var.prefix}-${var.env_short}"

  aks_api_url = var.env_short == "d" ? module.aks.fqdn : module.aks.private_fqdn

  monitor_action_group_slack_name    = "SlackPagoPA"
  monitor_action_group_email_name    = "PagoPA"
  monitor_action_group_opsgenie_name = "InfraOpsgenie"
  monitor_appinsights_name           = "${local.product}-appinsights"

  vnet_name                = "${local.product}-vnet"
  vnet_resource_group_name = "${local.product}-vnet-rg"

  acr_name                = replace(format("%s-common-acr", local.product), "-", "")
  acr_resource_group_name = "${local.product}-container-registry-rg"

  aks_name = "${local.project}-aks"

  vnet_integration_resource_group_name = "${local.product}-vnet-rg"
  vnet_integration_name                = "${local.product}-vnet-integration"

  # VNET
  vnet_core_resource_group_name = "${local.product}-vnet-rg"
  vnet_core_name                = "${local.product}-vnet"

  aks_logs_alerts = {}

  system_namespace     = "kube-system"
  devops_admin_sa_name = "azure-devops-admin"
}
