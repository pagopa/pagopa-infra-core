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
  icinga_image_version = "v4"

  # owners of the Entra ID application of Icinga Web (04_sso.tf)
  application_owners = [
    "matteo.alongi@pagopa.it",
    "marco.mari@pagopa.it",
    "umberto.coppolabottazzi@pagopa.it",
    "fabio.felici@pagopa.it"
  ]

  # ---------------------------------------------------------------------------
  # Icinga VM
  # ---------------------------------------------------------------------------
  icinga_vm_size = "Standard_D2as_v5"

  vnet_tools_name = "${local.product}-${local.location_short}-spoke-tools-vnet"
  vnet_tools_rg   = "${local.product}-${local.location_short}-network-hub-spoke-rg"

  # private DNS zone internal.<env>.platform.pagopa.it (internal.platform.pagopa.it in prod)
  internal_dns_zone_name = var.env_short != "p" ? "internal.${var.env}.platform.pagopa.it" : "internal.platform.pagopa.it"
  internal_dns_zone_rg   = "${local.product}-vnet-rg"
  icinga_dns_record_name = "icinga"
  icinga_fqdn            = "${local.icinga_dns_record_name}.${local.internal_dns_zone_name}"

  # Let's Encrypt certificate of icinga_fqdn in domain_kv (renewed by the certificates procedure)
  icinga_tls_cert_name = replace(local.icinga_fqdn, ".", "-")
  # versionless: icinga-tls-sync (icinga-configure.sh) always reads the latest version
  icinga_tls_secret_url = "${data.azurerm_key_vault.domain_kv.vault_uri}secrets/${local.icinga_tls_cert_name}"

  # identifies the Icinga configuration run, see 03_vm.tf
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
