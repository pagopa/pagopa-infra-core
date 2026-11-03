locals {
  # ---------------------------------------------------------------------------
  # General
  # ---------------------------------------------------------------------------
  prefix               = "pagopa"
  domain               = "cpm"
  location_short       = "itn"
  product              = "${local.prefix}-${var.env_short}"
  project              = "${local.product}-${var.location_short}-${local.domain}"
  location             = "italynorth"
  icinga_image_version = "v3"

  # ---------------------------------------------------------------------------
  # Icinga VM
  # ---------------------------------------------------------------------------
  icinga_vm_size = "Standard_B2ms"

  vnet_tools_name = "${local.product}-${local.location_short}-spoke-tools-vnet"
  vnet_tools_rg   = "${local.product}-${local.location_short}-network-hub-spoke-rg"

  # identifies the Icinga configuration run, see 00_vm.tf
  icinga_configure_hash = substr(sha256(jsonencode([
    filesha256("${path.module}/templates/icinga-configure.sh"),
    data.azurerm_key_vault_secret.icingadb_db_password.version,
    data.azurerm_key_vault_secret.icingaweb_db_password.version,
    data.azurerm_key_vault_secret.icingaweb_admin_password.version,
    data.azurerm_key_vault_secret.icinga_api_terraform_password.version,
    [for k, m in local.aks_icinga : m.kubeconfig_hash],
  ])), 0, 8)

  # ---------------------------------------------------------------------------
  # AKS
  # ---------------------------------------------------------------------------
  # cluster monitorati da Icinga, stessa naming di aks-platform
  # (<product>-<location>-<env>-aks); kubeconfig in <prefix>/config-<nome>
  aks_clusters = {
    for i in ["itn", "weu"] : i => {
      name                = "${local.product}-${i}-${var.env}-aks"
      resource_group_name = "${local.product}-${i}-${var.env}-aks-rg"
      kube_config_path    = "${var.k8s_kube_config_path_prefix}/config-${local.product}-${i}-${var.env}-aks"
    }
  }

  # chiave di local.aks_clusters => modulo aks_icinga (03_aks_icinga.tf)
  aks_icinga = {
    itn = module.aks_icinga_itn
    weu = module.aks_icinga_weu
  }
}
