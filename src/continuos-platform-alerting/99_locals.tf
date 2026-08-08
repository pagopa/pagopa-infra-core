locals {
  prefix  = "pagopa"
  product = "${local.prefix}-${var.env_short}"
  domain  = "core"
  project = "${local.product}-${var.location_short}-${local.domain}"


  monitor_resource_group_name = "${local.product}-monitor-rg"



  # Action group aggiuntivi per ambiente — vuoto se non prod
  env_action_groups = var.env_short == "p" ? [
    { action_group_name = "Opsgenie", resource_group_name = local.monitor_resource_group_name },
    { action_group_name = "PagoPA", resource_group_name = local.monitor_resource_group_name },
    { action_group_name = "SlackPagoPA", resource_group_name = local.monitor_resource_group_name }
  ] : [
    { action_group_name = "PagoPA", resource_group_name = local.monitor_resource_group_name },
    { action_group_name = "SlackPagoPA", resource_group_name = local.monitor_resource_group_name }

  ]


}

  