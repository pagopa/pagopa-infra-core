locals {
  prefix  = "pagopa"
  product = "${local.prefix}-${var.env_short}"
  domain  = "core"
  project = "${local.product}-${var.location_short}-${local.domain}"


  monitor_resource_group_name = "${local.product}-monitor-rg"



  # Action group aggiuntivi per ambiente — vuoto se non prod
 
  namespace_commands_map = {
    "Microsoft.Web/sites" = {
      icinga2_command = "..."
      resource_properties = "properties.defaultHostName"
    }
    # "Microsoft.App/containerApps" = {
    #    icinga2_command = "..."
    #    resource_properties = "properties.configuration.ingress.fqdn"
    # }
    "Microsoft.Cdn/profiles/afdendpoints" = {
       icinga2_command = "..."
       resource_properties = "properties.hostName"

    }
  }



}

  