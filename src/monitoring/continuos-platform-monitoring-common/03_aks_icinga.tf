# -----------------------------------------------------------------------------
# Identità di Icinga nei cluster AKS (vedi modules/aks_icinga)
# -----------------------------------------------------------------------------
module "aks_icinga_itn" {
  source = "./modules/aks_icinga"
  providers = {
    kubernetes = kubernetes.itn
  }

  aks_name                = local.aks_clusters["itn"].name
  aks_resource_group_name = local.aks_clusters["itn"].resource_group_name
  key_vault_id            = data.azurerm_key_vault.domain_kv.id
  tags                    = module.tag_config.tags
}

module "aks_icinga_weu" {
  source = "./modules/aks_icinga"
  providers = {
    kubernetes = kubernetes.weu
  }

  aks_name                = local.aks_clusters["weu"].name
  aks_resource_group_name = local.aks_clusters["weu"].resource_group_name
  key_vault_id            = data.azurerm_key_vault.domain_kv.id
  tags                    = module.tag_config.tags
}
