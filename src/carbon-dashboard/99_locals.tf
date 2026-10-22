locals {
  product = "${var.prefix}-${var.env_short}"
  project = "${var.prefix}-${var.env_short}-${var.location_short}-${var.domain}"

  # LAW
  log_analytics_workspace_name                = "${var.prefix}-${var.env_short}-${var.location_short}-core-law"
  log_analytics_workspace_resource_group_name = "${var.prefix}-${var.env_short}-${var.location_short}-core-monitor-rg"

  platform_dns_zone_name                = "${var.env == "prod" ? "" : "${var.env}."}platform.pagopa.it"
  platform_dns_zone_resource_group_name = "${local.product}-vnet-rg"
}
